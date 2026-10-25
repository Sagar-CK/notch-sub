import Foundation
import LocalAuthentication
import Security

struct LocalProviderCredential {
  var account: Account
  var credentials: Credentials
}

extension Provider {
  public static var additional: [Provider] {
    [.copilot, .cursor, .kimi, .minimax, .windsurf, .kiro, .opencode]
  }
  public var acceptsKey: Bool { [.zai, .kimi, .minimax, .opencode].contains(self) }
  public var allowedHosts: [String] {
    switch self {
    case .zai: return ["api.z.ai", "open.bigmodel.cn"]
    case .kimi: return ["api.kimi.ai", "api.kimi.com"]
    case .minimax: return ["www.minimax.io", "www.minimax.cn"]
    case .opencode: return ["opencode.ai"]
    case .copilot: return ["api.github.com"]
    case .cursor: return ["cursor.com"]
    case .kiro: return ["codewhisperer.us-east-1.amazonaws.com", "q.eu-central-1.amazonaws.com"]
    default: return []
    }
  }
}

extension LocalAccounts {
  public static func providerIdentity(_ provider: Provider, token: String, host: String) -> String {
    provider.rawValue + "-" + PrivateFiles.digest(Data("\(host)\u{0}\(token)".utf8)).prefix(24)
  }

  public func discoverAdditionalAccounts() -> [Account] {
    Provider.additional.flatMap { providerCandidates($0).map(\.account) }
  }

  public func additionalCredentials(for account: Account) throws -> Credentials {
    guard
      let candidate = providerCandidates(account.provider).first(where: {
        $0.account.id == account.id
      })
    else {
      throw TrackerError.message("Account changed · refresh")
    }
    if let issue = candidate.account.issue { throw TrackerError.message(issue) }
    return candidate.credentials
  }

  func providerCandidates(_ provider: Provider) -> [LocalProviderCredential] {
    let env = paths.environment
    var rows: [LocalProviderCredential] = []
    func add(
      _ token: String?, host: String, name: String = "", accountID: String? = nil,
      expiry: Date? = nil, headers: [String: String] = [:]
    ) {
      guard let token, !token.isEmpty, !token.contains(where: { $0.isNewline }),
        provider.allowedHosts.contains(host)
      else { return }
      if provider == .minimax && token.hasPrefix("sk-api-") { return }
      let id = Self.providerIdentity(provider, token: token, host: host)
      guard !rows.contains(where: { $0.account.id == id }) else { return }
      let issue =
        expiry.map { $0 <= Date().addingTimeInterval(30) } == true
        ? "Open \(provider.title) to renew sign-in" : nil
      rows.append(
        LocalProviderCredential(
          account: Account(
            id: id, provider: provider, name: name, isActive: true,
            source: .additionalLocal, issue: issue, canSwitch: false),
          credentials: Credentials(token: token, accountID: accountID, host: host, headers: headers)
        ))
    }
    func read(_ relative: String) -> [String: Any] {
      JSON.read(paths.home.appendingPathComponent(relative))
    }
    func configHome() -> URL {
      if let path = env["XDG_CONFIG_HOME"], path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
      }
      return paths.home.appendingPathComponent(".config")
    }
    switch provider {
    case .copilot:
      // Only Copilot-specific credentials. Do not reuse broad gh/PAT credentials silently.
      add(env["COPILOT_GITHUB_TOKEN"], host: "api.github.com")
      for name in ["hosts.json", "apps.json"] {
        let values = JSON.read(configHome().appendingPathComponent("github-copilot/\(name)"))
        for (key, raw) in values.sorted(by: { $0.key < $1.key }) {
          guard key == "github.com" || key.hasPrefix("github.com:"),
            let entry = raw as? [String: Any]
          else { continue }
          add(
            entry["oauth_token"] as? String, host: "api.github.com",
            name: entry["user"] as? String ?? "",
            accountID: entry["user"] as? String)
        }
      }
      let config = read(".copilot/config.json")
      let current = config["last_logged_in_user"] as? [String: Any] ?? [:]
      if current["host"] as? String == "https://github.com"
        || current["host"] as? String == "github.com"
      {
        let login = current["login"] as? String ?? ""
        let tokens = config["copilot_tokens"] as? [String: Any] ?? [:]
        for key in ["https://github.com:\(login)", "github.com:\(login)", login] {
          add(tokens[key] as? String, host: "api.github.com", name: login, accountID: login)
        }
      }
      if paths.home == FileManager.default.homeDirectoryForCurrentUser {
        for (account, data) in Self.providerKeychainItems(service: "copilot-cli") {
          // Service-scoped macOS records can be raw OAuth tokens or a JSON token record.
          let record = JSON.object(data)
          let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(
            in: .whitespacesAndNewlines)
          let token = (record["access_token"] ?? record["token"]) as? String ?? raw
          guard
            token?.hasPrefix("gho_") == true || token?.hasPrefix("ghu_") == true
              || token?.hasPrefix("github_pat_") == true
          else { continue }
          let publicHost = ["github.com", "https://github.com"].contains(
            current["host"] as? String ?? "")
          guard
            account == "github.com" || account.hasPrefix("github.com:")
              || account.hasPrefix("https://github.com:")
              || (publicHost && account == current["login"] as? String)
          else { continue }
          add(
            token, host: "api.github.com", name: record["login"] as? String ?? "",
            accountID: record["login"] as? String)
        }
      }
    case .cursor:
      let db = paths.home.appendingPathComponent(
        "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
      let appToken = LocalDatabase.text(LocalDatabase.value(at: db, key: "cursorAuth/accessToken"))
      let cli = JSON.read(configHome().appendingPathComponent("cursor/auth.json"))
      // The editor is authoritative when both are signed in. Do not silently switch on HTTP failure.
      let token = appToken ?? cli["accessToken"] as? String
      if let token {
        let claims = JSON.jwt(token)
        add(
          token, host: "cursor.com", name: claims["email"] as? String ?? "",
          accountID: claims["sub"] as? String, expiry: JSON.date(claims["exp"]) ?? .distantPast)
      }
    case .kimi:
      let base = env["KIMI_CODE_BASE_URL"] ?? "https://api.kimi.com/coding/v1"
      if let url = URL(string: base), url.scheme == "https", url.user == nil, url.password == nil,
        let host = url.host, provider.allowedHosts.contains(host)
      {
        add(env["KIMI_CODE_API_KEY"], host: host)
      }
      // The official CLI scopes credential filenames to each region. Never try a token on another host.
      if env["KIMI_CODE_BASE_URL"] == nil && env["KIMI_CODE_OAUTH_HOST"] == nil
        && env["KIMI_OAUTH_HOST"] == nil
      {
        let home =
          env["KIMI_CODE_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
          ?? paths.home.appendingPathComponent(".kimi-code")
        let device =
          (try? String(contentsOf: home.appendingPathComponent("device_id"), encoding: .utf8))?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        var headers: [String: String] = [:]
        if let device, !device.isEmpty,
          device.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) })
        {
          headers = ["X-Msh-Platform": "kimi_cli", "X-Msh-Device-Id": device]
        }
        let globalScope =
          "{\"oauthHost\":\"https://auth.kimi.ai\",\"baseUrl\":\"https://api.kimi.ai/coding/v1\"}"
        let globalKey = "kimi-code-env-" + PrivateFiles.digest(Data(globalScope.utf8)).prefix(16)
        for (key, host) in [("kimi-code", "api.kimi.com"), (globalKey, "api.kimi.ai")] {
          let oauth = JSON.read(home.appendingPathComponent("credentials/\(key).json"))
          add(
            oauth["access_token"] as? String, host: host,
            expiry: JSON.date(oauth["expires_at"]) ?? .distantPast, headers: headers)
        }
      }
    case .minimax:
      add(env["MINIMAX_CODING_API_KEY"], host: "www.minimax.io")
      if let key = env["MINIMAX_API_KEY"], key.hasPrefix("sk-cp-") {
        add(key, host: "www.minimax.io")
      }
      add(env["MINIMAX_CN_API_KEY"], host: "www.minimax.cn")
    case .opencode:
      add(env["OPENCODE_API_KEY"], host: "opencode.ai")
    case .kiro:
      let directory =
        env["KIRO_DATA_DIR"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        ?? paths.home.appendingPathComponent("Library/Application Support/kiro-cli")
      let db = directory.appendingPathComponent("data.sqlite3")
      let auth =
        LocalDatabase.value(at: db, table: "auth_kv", key: "kirocli:odic:token").map(JSON.object)
        ?? [:]
      let profile =
        LocalDatabase.value(at: db, table: "state", key: "api.codewhisperer.profile").map(
          JSON.object) ?? [:]
      if let arn = profile["arn"] as? String, let host = Self.kiroHost(profileARN: arn) {
        add(
          auth["access_token"] as? String, host: host, accountID: arn,
          expiry: JSON.date(auth["expires_at"]))
      }
    case .windsurf:
      // The editor's own plan cache is supported without importing any browser session.
      for folder in ["Devin", "Windsurf", "Windsurf - Next"] {
        let db = paths.home.appendingPathComponent(
          "Library/Application Support/\(folder)/User/globalStorage/state.vscdb")
        guard LocalDatabase.value(at: db, key: "windsurf.settings.cachedPlanInfo") != nil else {
          continue
        }
        let id = "windsurf-" + PrivateFiles.digest(Data(db.path.utf8)).prefix(24)
        rows.append(
          LocalProviderCredential(
            account: Account(
              id: id, provider: .windsurf, name: "",
              isActive: true, source: .windsurfCache(db), canSwitch: false),
            credentials: Credentials(token: "")))
        break
      }
    default: break
    }
    if [.kimi, .minimax, .opencode].contains(provider) {
      // Keys configured for the exact provider in OpenCode or Claude Code are safe to reuse.
      let dataHome =
        env["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        ?? paths.home.appendingPathComponent(".local/share")
      let auth = JSON.read(dataHome.appendingPathComponent("opencode/auth.json"))
      let names: [(String, String)] =
        provider == .kimi
        ? [
          ("kimi-code-plan-cn", "api.kimi.com"), ("kimi-code-plan-global", "api.kimi.ai"),
          ("kimi-for-coding", "api.kimi.com"), ("kimi-for-coding-international", "api.kimi.ai"),
        ]
        : provider == .minimax
          ? [
            ("minimax-coding-plan", "www.minimax.io"),
            ("minimax-cn-coding-plan", "www.minimax.cn"),
          ]
          : [("opencode-go", "opencode.ai")]
      for (key, host) in names {
        if let item = auth[key] as? [String: Any], item["type"] as? String == "api" {
          add(item["key"] as? String, host: host)
        }
      }
      let settings =
        JSON.read(paths.claude.appendingPathComponent("settings.json"))["env"] as? [String: Any]
        ?? [:]
      if let raw = settings["ANTHROPIC_BASE_URL"] as? String, let url = URL(string: raw),
        url.scheme == "https",
        url.user == nil, url.password == nil, let host = url.host
      {
        let mapped =
          provider == .minimax
          ? [
            "api.minimax.io": "www.minimax.io", "api.minimaxi.com": "www.minimax.cn",
            "api.minimax.cn": "www.minimax.cn",
          ][host]
          : host
        if let mapped {
          add(
            (settings["ANTHROPIC_AUTH_TOKEN"] ?? settings["ANTHROPIC_API_KEY"]) as? String,
            host: mapped)
        }
      }
    }
    return rows
  }

  public static func kiroHost(profileARN: String) -> String? {
    let pieces = profileARN.split(separator: ":", omittingEmptySubsequences: false)
    guard pieces.count == 6, pieces[0] == "arn", pieces[1] == "aws", pieces[2] == "codewhisperer",
      pieces[5].hasPrefix("profile/")
    else { return nil }
    return [
      "us-east-1": "codewhisperer.us-east-1.amazonaws.com",
      "eu-central-1": "q.eu-central-1.amazonaws.com",
    ][String(pieces[3])]
  }

  private static func providerKeychainItems(service: String) -> [(String, Data)] {
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecReturnAttributes as String: true,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll,
      kSecUseAuthenticationContext as String: context,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let items = result as? [[String: Any]]
    else { return [] }
    return items.compactMap { item in
      guard let account = item[kSecAttrAccount as String] as? String,
        let data = item[kSecValueData as String] as? Data
      else { return nil }
      return (account, data)
    }
  }
}
