import Foundation
import LocalAuthentication
import Security

extension LocalAccounts {
  public func discoverGoogleAccounts() -> [Account] {
    var accounts: [Account] = []
    let settings = JSON.read(paths.gemini.appendingPathComponent("settings.json"))
    let auth = (settings["security"] as? [String: Any])?["auth"] as? [String: Any]
    let selected = auth?["selectedType"] as? String
    // API keys and Vertex credentials have different quotas from Code Assist subscriptions.
    if selected == nil || selected == "oauth-personal" {
      let file = paths.gemini.appendingPathComponent("oauth_creds.json")
      let fileData = JSON.read(file)
      let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        ".gemini")
      let hasKeychain = paths.gemini == defaultDirectory && Self.hasGeminiKeychainItem()
      if hasKeychain || Self.googleToken(fileData) != nil {
        let source: AuthSource = hasKeychain ? .geminiKeychain : .geminiFile(file)
        // The keychain is authoritative after CLI migration; never fall back to a stale file.
        let claims = hasKeychain ? [:] : JSON.jwt(fileData["id_token"] as? String)
        let email = claims["email"] as? String ?? googleEmail()
        let identity = email?.lowercased() ?? PrivateFiles.digest(Data(paths.gemini.path.utf8))
        accounts.append(
          Account(
            id: "gemini-" + PrivateFiles.digest(Data(identity.utf8)).prefix(24), provider: .gemini,
            name: email?.components(separatedBy: "@").first ?? "Google account", email: email,
            isActive: true, source: source, canSwitch: false))
      }
    }
    if let executable = AntigravityUsage.executable(
      home: paths.home, environment: paths.environment)
    {
      // The usage command does not report an account identity. Do not attach a Google email or paid plan.
      accounts.append(
        Account(
          id: "antigravity-cli", provider: .antigravity, name: "Local CLI",
          isActive: false, source: .antigravityCLI(executable), canSwitch: false))
    }
    return accounts
  }

  private func googleEmail() -> String? {
    let value =
      JSON.read(paths.gemini.appendingPathComponent("google_accounts.json"))["active"] as? String
    return value?.isEmpty == false ? value : nil
  }

  private static func hasGeminiKeychainItem() -> Bool {
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "gemini-cli-oauth", kSecAttrAccount as String: "main-account",
      kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseAuthenticationContext as String: context,
    ]
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
  }

  public static func googleToken(_ json: [String: Any]) -> String? {
    let token =
      (json["token"] as? [String: Any])?["accessToken"] as? String ?? json["access_token"]
      as? String
    return token?.isEmpty == false ? token : nil
  }

  public func geminiCredentials(for account: Account, at now: Date = Date()) throws -> Credentials {
    let json: [String: Any]
    switch account.source {
    case .geminiFile(let file): json = JSON.read(file)
    case .geminiKeychain:
      json = JSON.object(
        try KeychainStore.read(service: "gemini-cli-oauth", account: "main-account"))
    default: throw TrackerError.message("Gemini sign-in needed")
    }
    let claims = JSON.jwt(json["id_token"] as? String)
    let currentEmail = claims["email"] as? String ?? googleEmail()
    guard currentEmail?.lowercased() == account.email?.lowercased(),
      let token = Self.googleToken(json)
    else {
      throw TrackerError.message("Account changed · refresh")
    }
    let nested = json["token"] as? [String: Any]
    if let expiry = JSON.date(nested?["expiresAt"] ?? json["expiry_date"]),
      expiry <= now.addingTimeInterval(30)
    {
      throw TrackerError.message("Open Gemini CLI to renew sign-in")
    }
    let project =
      paths.environment["GOOGLE_CLOUD_PROJECT"] ?? paths.environment["GOOGLE_CLOUD_PROJECT_ID"]
    return Credentials(token: token, accountID: currentEmail, projectID: project)
  }
}
