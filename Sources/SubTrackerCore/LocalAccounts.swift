import CryptoKit
import Darwin
import Foundation
import Security

public struct LocalPaths: Sendable {
  public var home: URL
  public var codex: URL
  public var claude: URL
  public var gemini: URL
  public var environment: [String: String]
  public var support: URL
  public init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.home = home
    self.environment = environment
    gemini = (environment["GEMINI_CLI_HOME"].map { URL(fileURLWithPath: $0) } ?? home)
      .appendingPathComponent(".gemini")
    codex =
      environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
      ?? home.appendingPathComponent(".codex")
    claude =
      environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
      ?? home.appendingPathComponent(".claude")
    support = home.appendingPathComponent("Library/Application Support/SubTracker")
  }
  public var claudeMetadata: URL {
    claude == home.appendingPathComponent(".claude")
      ? home.appendingPathComponent(".claude.json") : claude.appendingPathComponent(".claude.json")
  }
}

public enum PrivateFiles {
  public static func directory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  }
  public static func write(_ data: Data, to url: URL) throws {
    let fm = FileManager.default
    if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
      throw TrackerError.message("Refusing to replace a symlink")
    }
    try directory(url.deletingLastPathComponent())
    let tmp = url.deletingLastPathComponent().appendingPathComponent(
      ".subtracker-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tmp) }
    guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
    else { throw TrackerError.message("Could not save private data") }
    guard rename(tmp.path, url.path) == 0 else {
      throw TrackerError.message("Could not replace private data")
    }
  }
  public static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

public enum KeychainStore {
  public static let service = "com.sagar.subtracker.accounts"
  public static func read(service: String = service, account: String? = nil) throws -> Data {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let account { query[kSecAttrAccount as String] = account }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      throw TrackerError.message("Keychain access needed")
    }
    return data
  }
  public static func write(_ data: Data, service: String = service, account: String? = nil) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
    ]
    if let account { query[kSecAttrAccount as String] = account }
    var status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      query[kSecAttrAccount as String] = account ?? NSUserName()
      query[kSecValueData as String] = data
      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(query as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw TrackerError.message("Could not save to Keychain") }
  }
  // Claude's own item may grant access to Apple's security utility but not a new unsigned app.
  // Arguments identify the item only. Credential bytes remain inside the pipe, never in argv or logs.
  public static func readClaude() throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: killer)
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    killer.cancel()
    guard process.terminationStatus == 0, !data.isEmpty else {
      throw TrackerError.message("Claude sign-in needed")
    }
    return data
  }
}

public struct SavedProfile: Codable, Sendable, Equatable {
  public var id: String
  public var provider: Provider
  public var name: String
  public var email: String?
  public var plan: String?
  public var identity: String
}

public struct Credentials: Sendable {
  public var token: String
  public var accountID: String?
  public var host: String = "api.z.ai"
  public var projectID: String? = nil
  public var headers: [String: String] = [:]
}

public struct LocalAccounts: Sendable {
  public let paths: LocalPaths
  public init(paths: LocalPaths = LocalPaths()) { self.paths = paths }
  public var savedProfiles: [SavedProfile] {
    guard let data = try? Data(contentsOf: paths.support.appendingPathComponent("profiles.json"))
    else { return [] }
    return (try? JSONDecoder().decode([SavedProfile].self, from: data)) ?? []
  }
  public static func codexIdentity(_ json: [String: Any]) -> String? {
    guard let tokens = json["tokens"] as? [String: Any],
      let account = tokens["account_id"] as? String
    else { return nil }
    let jwt = JSON.jwt(tokens["id_token"] as? String)
    let auth = jwt["https://api.openai.com/auth"] as? [String: Any] ?? [:]
    let user =
      auth["chatgpt_user_id"] as? String ?? jwt["sub"] as? String ?? jwt["email"] as? String ?? ""
    return "codex-" + PrivateFiles.digest(Data("\(account):\(user)".utf8)).prefix(24)
  }
  public func codexFiles() -> [URL] {
    var urls = [paths.codex.appendingPathComponent("auth.json")]
    for folder in [
      paths.codex.appendingPathComponent("accounts"),
      paths.home.appendingPathComponent(".codex-swap/accounts"),
    ] {
      urls +=
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
        ?? [])
        .filter { $0.lastPathComponent.hasSuffix(".auth.json") }.sorted { $0.path < $1.path }
    }
    return urls
  }
  public func discover() -> [Account] {
    let active = Self.codexIdentity(JSON.read(paths.codex.appendingPathComponent("auth.json")))
    let registry = JSON.read(paths.codex.appendingPathComponent("accounts/registry.json"))
    let registryAccounts = registry["accounts"] as? [[String: Any]] ?? []
    var result: [Account] = []
    var versions: [String: Double] = [:]
    for file in codexFiles() {
      let json = JSON.read(file)
      guard let id = Self.codexIdentity(json), let tokens = json["tokens"] as? [String: Any],
        tokens["access_token"] as? String != nil
      else { continue }
      let jwt = JSON.jwt(tokens["id_token"] as? String)
      let auth = jwt["https://api.openai.com/auth"] as? [String: Any] ?? [:]
      let email = jwt["email"] as? String
      let meta = registryAccounts.first {
        $0["chatgpt_account_id"] as? String == tokens["account_id"] as? String
          && (email == nil || $0["email"] as? String == email)
      }
      let alias = meta?["alias"] as? String
      let name =
        alias.flatMap { $0.isEmpty ? nil : $0 } ?? email?.components(separatedBy: "@").first
        ?? "Codex account"
      let plan = auth["chatgpt_plan_type"] as? String ?? meta?["plan"] as? String
      var cached: UsageSnapshot?
      if let usage = meta?["last_usage"] as? [String: Any],
        let at = JSON.date(meta?["last_usage_at"])
      {
        cached = UsageParser.codex(usage, at: at, cached: true)
      }
      let isLiveFile = file == paths.codex.appendingPathComponent("auth.json")
      let version =
        isLiveFile
        ? Double.greatestFiniteMagnitude
        : (JSON.date(json["last_refresh"])?.timeIntervalSince1970 ?? JSON.number(
          JSON.jwt(tokens["access_token"] as? String)["iat"]) ?? 0)
      guard version > (versions[id] ?? -1) else { continue }
      versions[id] = version
      let account = Account(
        id: id, provider: .codex, name: name, email: email, plan: plan, isActive: id == active,
        source: .codex(file), usage: cached)
      result.removeAll { $0.id == id }
      result.append(account)
    }
    let metadata = JSON.read(paths.claudeMetadata)["oauthAccount"] as? [String: Any] ?? [:]
    let claudeID = metadata["accountUuid"] as? String
    if let claudeID {
      let email = metadata["emailAddress"] as? String
      result.append(
        Account(
          id: "claude-\(claudeID)", provider: .claude,
          name: metadata["displayName"] as? String ?? email?.components(separatedBy: "@").first
            ?? "Claude account",
          email: email,
          plan: metadata["organizationRateLimitTier"] as? String ?? metadata["organizationType"]
            as? String,
          isActive: true, source: .claudeLocal))
    }
    for profile in savedProfiles where !result.contains(where: { $0.id == profile.identity }) {
      let configuredEnv =
        JSON.read(paths.claude.appendingPathComponent("settings.json"))["env"] as? [String: Any]
        ?? [:]
      let canSwitch =
        profile.provider == .claude || profile.provider == .codex
        || (profile.provider == .zai
          && Self.zaiHost(configuredEnv["ANTHROPIC_BASE_URL"] as? String) != nil)
      result.append(
        Account(
          id: profile.identity, provider: profile.provider, name: profile.name,
          email: profile.email, plan: profile.plan,
          source: .vault(profile.id), canSwitch: canSwitch))
    }
    // Read only documented local JSON configurations. No shell files, browser databases, or unrelated secrets.
    let settings = paths.claude.appendingPathComponent("settings.json")
    let env = JSON.read(settings)["env"] as? [String: Any] ?? [:]
    if let host = Self.zaiHost(env["ANTHROPIC_BASE_URL"] as? String),
      let key = (env["ANTHROPIC_AUTH_TOKEN"] ?? env["ANTHROPIC_API_KEY"]) as? String, !key.isEmpty
    {
      let id = "zai-" + PrivateFiles.digest(Data(key.utf8)).prefix(24)
      result.removeAll { $0.id == id }
      result.append(
        Account(
          id: id, provider: .zai, name: host == "api.z.ai" ? "Coding Plan" : "BigModel",
          isActive: true, source: .zaiSettings(settings)))
    }
    let envVars = ProcessInfo.processInfo.environment
    if let key = envVars["ZAI_API_KEY"] ?? envVars["Z_AI_API_KEY"], !key.isEmpty {
      let id = "zai-" + PrivateFiles.digest(Data(key.utf8)).prefix(24)
      if !result.contains(where: { $0.id == id }) {
        result.append(
          Account(
            id: id, provider: .zai, name: "Coding Plan", isActive: true, source: .zaiEnvironment))
      }
    }
    result += discoverGoogleAccounts()
    let additional = discoverAdditionalAccounts()
    result.removeAll { a in additional.contains { $0.id == a.id } }
    result += additional
    return result.sorted {
      if $0.provider != $1.provider {
        return Provider.allCases.firstIndex(of: $0.provider)! < Provider.allCases.firstIndex(
          of: $1.provider)!
      }
      if $0.isActive != $1.isActive { return $0.isActive }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
  public static func zaiHost(_ base: String?) -> String? {
    guard let base, let url = URL(string: base), url.scheme == "https", let host = url.host,
      ["api.z.ai", "open.bigmodel.cn"].contains(host)
    else { return nil }
    return host
  }
  public func claudeCredentialData() throws -> Data {
    let file = paths.claude.appendingPathComponent(".credentials.json")
    if FileManager.default.fileExists(atPath: file.path) { return try Data(contentsOf: file) }
    guard paths.claude == paths.home.appendingPathComponent(".claude") else {
      throw TrackerError.message("Sign in to this Claude profile")
    }
    return try KeychainStore.readClaude()
  }
  public func credentials(for account: Account) throws -> Credentials {
    switch account.source {
    case .codex(let url):
      let json = JSON.read(url)
      guard Self.codexIdentity(json) == account.id, let tokens = json["tokens"] as? [String: Any],
        let token = tokens["access_token"] as? String
      else { throw TrackerError.message("Account changed · refresh") }
      return Credentials(token: token, accountID: tokens["account_id"] as? String)
    case .claudeLocal:
      let metadata = JSON.read(paths.claudeMetadata)["oauthAccount"] as? [String: Any] ?? [:]
      guard "claude-\(metadata["accountUuid"] as? String ?? "")" == account.id else {
        throw TrackerError.message("Account changed · refresh")
      }
      let json = JSON.object(try claudeCredentialData())
      guard let oauth = json["claudeAiOauth"] as? [String: Any],
        let token = oauth["accessToken"] as? String
      else { throw TrackerError.message("Claude sign-in needed") }
      return Credentials(token: token)
    case .vault(let id):
      let json = JSON.object(try KeychainStore.read(account: id))
      if account.provider == .claude, let oauth = json["claudeAiOauth"] as? [String: Any],
        let token = oauth["accessToken"] as? String
      {
        return Credentials(token: token)
      }
      if account.provider.acceptsKey, let token = json["token"] as? String {
        return Credentials(token: token, host: json["host"] as? String ?? "api.z.ai")
      }
      throw TrackerError.message("Sign-in needed")
    case .zaiSettings(let url):
      let env = JSON.read(url)["env"] as? [String: Any] ?? [:]
      guard let host = Self.zaiHost(env["ANTHROPIC_BASE_URL"] as? String),
        let key = (env["ANTHROPIC_AUTH_TOKEN"] ?? env["ANTHROPIC_API_KEY"]) as? String
      else { throw TrackerError.message("Z.ai key needed") }
      guard "zai-" + PrivateFiles.digest(Data(key.utf8)).prefix(24) == account.id else {
        throw TrackerError.message("Account changed · refresh")
      }
      return Credentials(token: key, host: host)
    case .zaiEnvironment:
      guard
        let key = ProcessInfo.processInfo.environment["ZAI_API_KEY"]
          ?? ProcessInfo.processInfo.environment["Z_AI_API_KEY"]
      else { throw TrackerError.message("Z.ai key needed") }
      guard "zai-" + PrivateFiles.digest(Data(key.utf8)).prefix(24) == account.id else {
        throw TrackerError.message("Account changed · refresh")
      }
      return Credentials(token: key)
    case .geminiFile, .geminiKeychain:
      return try geminiCredentials(for: account)
    case .antigravityCLI:
      throw TrackerError.message("Read usage through Antigravity CLI")
    case .additionalLocal: return try additionalCredentials(for: account)
    case .windsurfCache: throw TrackerError.message("Read the editor's usage cache")
    case .unavailable: throw TrackerError.message("Connect Coding Plan")
    }
  }
  public func saveClaude() throws {
    let metadata = JSON.read(paths.claudeMetadata)["oauthAccount"] as? [String: Any] ?? [:]
    guard let identity = metadata["accountUuid"] as? String else {
      throw TrackerError.message("Sign in to Claude Code first")
    }
    let json = JSON.object(try claudeCredentialData())
    guard let oauth = json["claudeAiOauth"] as? [String: Any] else {
      throw TrackerError.message("Claude sign-in needed")
    }
    let id = "claude-\(identity)"
    try KeychainStore.write(
      try JSON.data(["claudeAiOauth": oauth, "oauthAccount": metadata]), account: id)
    let email = metadata["emailAddress"] as? String
    let profile = SavedProfile(
      id: id, provider: .claude, name: metadata["displayName"] as? String ?? email ?? "Claude",
      email: email,
      plan: metadata["organizationRateLimitTier"] as? String, identity: id)
    try saveProfile(profile)
  }
  public func saveCurrentCodex() throws {
    let file = paths.codex.appendingPathComponent("auth.json")
    guard let data = try? Data(contentsOf: file), let id = Self.codexIdentity(JSON.object(data))
    else { return }
    try PrivateFiles.write(data, to: paths.codex.appendingPathComponent("accounts/\(id).auth.json"))
  }
  public func saveZai(name: String, token: String, host: String) throws {
    guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      ["api.z.ai", "open.bigmodel.cn"].contains(host)
    else { throw TrackerError.message("Enter a valid key") }
    let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    let id = "zai-" + PrivateFiles.digest(Data(token.utf8)).prefix(24)
    try KeychainStore.write(try JSON.data(["token": token, "host": host]), account: id)
    try saveProfile(
      SavedProfile(id: id, provider: .zai, name: name.isEmpty ? "Coding Plan" : name, identity: id))
  }
  func saveProfile(_ profile: SavedProfile) throws {
    var profiles = savedProfiles.filter { $0.identity != profile.identity }
    profiles.append(profile)
    try PrivateFiles.write(
      JSONEncoder().encode(profiles), to: paths.support.appendingPathComponent("profiles.json"))
  }
}
