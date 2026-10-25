import Darwin
import Foundation

public struct FileChange {
  public var url: URL
  public var before: Data?
  public var after: Data
  public init(url: URL, before: Data?, after: Data) {
    self.url = url
    self.before = before
    self.after = after
  }
}

public enum FileTransaction {
  public static func apply(_ changes: [FileChange]) throws {
    guard Set(changes.map(\.url)).count == changes.count else {
      throw TrackerError.message("Conflicting account files")
    }
    for change in changes {
      guard (try? Data(contentsOf: change.url)) == change.before else {
        throw TrackerError.message("Sign-in changed · refresh and retry")
      }
      guard (try? change.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
      else { throw TrackerError.message("Cannot switch a symlinked sign-in") }
    }
    var applied: [FileChange] = []
    do {
      for change in changes {
        guard (try? Data(contentsOf: change.url)) == change.before else {
          throw TrackerError.message("Sign-in changed · refresh and retry")
        }
        try PrivateFiles.write(change.after, to: change.url)
        applied.append(change)
      }
    } catch {
      for change in applied.reversed() where (try? Data(contentsOf: change.url)) == change.after {
        if let before = change.before {
          try? PrivateFiles.write(before, to: change.url)
        } else {
          try? FileManager.default.removeItem(at: change.url)
        }
      }
      throw error
    }
  }
}

extension LocalAccounts {
  public func switchAccount(_ account: Account) throws {
    try PrivateFiles.directory(paths.support)
    let lockPath = paths.support.appendingPathComponent("switch.lock").path
    let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw TrackerError.message("Could not lock account settings") }
    defer {
      flock(fd, LOCK_UN)
      close(fd)
    }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      throw TrackerError.message("Another switch is in progress")
    }
    switch account.provider {
    case .codex: try switchCodex(account)
    case .claude: try switchClaude(account)
    case .zai: try switchZai(account)
    case .gemini, .antigravity:
      throw TrackerError.message("Manage this sign-in in \(account.provider.title)")
    }
  }

  private func switchCodex(_ account: Account) throws {
    guard case .codex(let target) = account.source else {
      throw TrackerError.message("Saved sign-in missing")
    }
    let targetData = try Data(contentsOf: target)
    guard Self.codexIdentity(JSON.object(targetData)) == account.id else {
      throw TrackerError.message("Account changed · refresh")
    }
    let live = paths.codex.appendingPathComponent("auth.json")
    let liveData = try? Data(contentsOf: live)
    let oldIdentity = liveData.flatMap { Self.codexIdentity(JSON.object($0)) }
    if oldIdentity == account.id { return }
    var changes: [FileChange] = []
    // Refresh tokens rotate. Preserve the current live token in every matching existing profile.
    if let liveData, let oldIdentity {
      let backup = paths.support.appendingPathComponent("backups/\(oldIdentity).auth.json")
      try PrivateFiles.write(liveData, to: backup)
      for file in codexFiles() where file != live && file != target {
        if let before = try? Data(contentsOf: file),
          Self.codexIdentity(JSON.object(before)) == oldIdentity
        {
          changes.append(FileChange(url: file, before: before, after: liveData))
        }
      }
      // If the current account has never been saved, retain it in the Codex accounts directory.
      if !changes.contains(where: { $0.url.path.hasPrefix(paths.codex.path) }) {
        let save = paths.codex.appendingPathComponent("accounts/\(oldIdentity).auth.json")
        changes.append(FileChange(url: save, before: try? Data(contentsOf: save), after: liveData))
      }
    }
    changes.append(FileChange(url: live, before: liveData, after: targetData))
    let registryURL = paths.codex.appendingPathComponent("accounts/registry.json")
    if let before = try? Data(contentsOf: registryURL) {
      var registry = JSON.object(before)
      let tokens = JSON.object(targetData)["tokens"] as? [String: Any] ?? [:]
      if let meta = (registry["accounts"] as? [[String: Any]])?.first(where: {
        $0["chatgpt_account_id"] as? String == tokens["account_id"] as? String
          && (account.email == nil || $0["email"] as? String == account.email)
      }), let key = meta["account_key"] {
        registry["active_account_key"] = key
        registry["active_account_activated_at_ms"] = Int(Date().timeIntervalSince1970 * 1000)
        changes.append(FileChange(url: registryURL, before: before, after: try JSON.data(registry)))
      }
    }
    // The legacy codex-swap helper must not later sync this login into the old account.
    let swapState = paths.home.appendingPathComponent(".codex-swap/state.json")
    if let before = try? Data(contentsOf: swapState) {
      var state = JSON.object(before)
      let swapDir = paths.home.appendingPathComponent(".codex-swap/accounts")
      let matching = codexFiles().first {
        $0.deletingLastPathComponent() == swapDir && Self.codexIdentity(JSON.read($0)) == account.id
      }
      state["active"] =
        matching.map { $0.lastPathComponent.replacingOccurrences(of: ".auth.json", with: "") }
        as Any? ?? NSNull()
      changes.append(FileChange(url: swapState, before: before, after: try JSON.data(state)))
    }
    // Revalidate the target immediately before committing; never refresh tokens ourselves.
    guard (try? Data(contentsOf: target)) == targetData else {
      throw TrackerError.message("Sign-in changed · refresh and retry")
    }
    try FileTransaction.apply(changes)
  }

  private func switchClaude(_ account: Account) throws {
    guard case .vault(let id) = account.source else {
      throw TrackerError.message("Save this Claude sign-in first")
    }
    let target = JSON.object(try KeychainStore.read(account: id))
    guard let oauth = target["claudeAiOauth"] as? [String: Any],
      let metadata = target["oauthAccount"] as? [String: Any],
      "claude-\(metadata["accountUuid"] as? String ?? "")" == account.id
    else { throw TrackerError.message("Saved Claude sign-in is incomplete") }
    let currentData = try claudeCredentialData()
    var current = JSON.object(currentData)
    let metaBefore = try Data(contentsOf: paths.claudeMetadata)
    var meta = JSON.object(metaBefore)
    try saveClaude()  // Preserve the latest rotating token before replacing it.
    current["claudeAiOauth"] = oauth
    meta["oauthAccount"] = metadata
    let after = try JSON.data(current)
    let metaAfter = try JSON.data(meta)
    guard try claudeCredentialData() == currentData else {
      throw TrackerError.message("Claude sign-in changed · retry")
    }
    let credentialsFile = paths.claude.appendingPathComponent(".credentials.json")
    if FileManager.default.fileExists(atPath: credentialsFile.path) {
      try FileTransaction.apply([
        FileChange(url: credentialsFile, before: currentData, after: after),
        FileChange(url: paths.claudeMetadata, before: metaBefore, after: metaAfter),
      ])
    } else {
      try FileTransaction.apply([
        FileChange(url: paths.claudeMetadata, before: metaBefore, after: metaAfter)
      ])
      do { try KeychainStore.write(after, service: "Claude Code-credentials") } catch {
        if (try? Data(contentsOf: paths.claudeMetadata)) == metaAfter {
          try? PrivateFiles.write(metaBefore, to: paths.claudeMetadata)
        }
        throw error
      }
    }
  }

  private func switchZai(_ account: Account) throws {
    guard case .vault = account.source else { return }
    let credentials = try credentials(for: account)
    let url = paths.claude.appendingPathComponent("settings.json")
    guard let before = try? Data(contentsOf: url) else {
      throw TrackerError.message("Switch this account in ZCode settings")
    }
    var settings = JSON.object(before)
    var env = settings["env"] as? [String: Any] ?? [:]
    guard Self.zaiHost(env["ANTHROPIC_BASE_URL"] as? String) != nil else {
      throw TrackerError.message("Switch this account in ZCode settings")
    }
    // Preserve the outgoing Z.ai profile before activating a new key in an existing Z.ai configuration.
    if let oldKey = (env["ANTHROPIC_AUTH_TOKEN"] ?? env["ANTHROPIC_API_KEY"]) as? String,
      let host = Self.zaiHost(env["ANTHROPIC_BASE_URL"] as? String)
    {
      try saveZai(name: "Coding Plan", token: oldKey, host: host)
    }
    let keyField = env["ANTHROPIC_AUTH_TOKEN"] != nil ? "ANTHROPIC_AUTH_TOKEN" : "ANTHROPIC_API_KEY"
    env[keyField] = credentials.token
    env["ANTHROPIC_BASE_URL"] = "https://\(credentials.host)/api/anthropic"
    settings["env"] = env
    try FileTransaction.apply([FileChange(url: url, before: before, after: try JSON.data(settings))]
    )
  }
}
