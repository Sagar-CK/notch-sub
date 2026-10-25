import Foundation

extension UsageClient {
  func fetchCodingPlan(
    provider: Provider, token: String, host: String, accountID: String?, headers: [String: String]
  ) async throws -> UsageSnapshot {
    guard provider.allowedHosts.contains(host), !token.isEmpty,
      !token.contains(where: { $0.isNewline })
    else {
      throw TrackerError.message("Unsupported provider credentials")
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForResource = 25
    let session = URLSession(
      configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    func request(_ path: String, body: [String: Any]? = nil, cookie: String? = nil) async throws
      -> [String: Any]
    {
      guard path.hasPrefix("/"), !path.hasPrefix("//"),
        let url = URL(string: "https://\(host)\(path)")
      else { throw TrackerError.message("Unsupported provider endpoint") }
      var request = URLRequest(url: url, timeoutInterval: 20)
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("SubTracker", forHTTPHeaderField: "User-Agent")
      if let cookie {
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
      } else {
        request.setValue(
          "\(provider == .copilot ? "token" : "Bearer") \(token)",
          forHTTPHeaderField: "Authorization")
      }
      if provider == .copilot {
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
      }
      if provider == .kimi {
        for key in ["X-Msh-Platform", "X-Msh-Device-Id"] {
          if let value = headers[key] { request.setValue(value, forHTTPHeaderField: key) }
        }
      }
      if let body {
        request.httpMethod = "POST"
        request.setValue(
          provider == .kiro ? "application/x-amz-json-1.0" : "application/json",
          forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSON.data(body)
      }
      if provider == .kiro {
        request.setValue(
          "AmazonCodeWhispererService.GetUsageLimits", forHTTPHeaderField: "X-Amz-Target")
      }
      let (data, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else {
        throw TrackerError.message("No response")
      }
      switch response.statusCode {
      case 200: return JSON.object(data)
      case 401, 403: throw TrackerError.message("Open \(provider.title) to check sign-in")
      case 429: throw TrackerError.message("Rate limited · try later")
      default: throw TrackerError.message("Provider unavailable (\(response.statusCode))")
      }
    }
    switch provider {
    case .copilot:
      if let accountID, !accountID.isEmpty {
        let user = try await request("/user")
        guard (user["login"] as? String)?.lowercased() == accountID.lowercased() else {
          throw TrackerError.message("Account changed · refresh")
        }
      }
      return try UsageParser.copilot(await request("/copilot_internal/user"))
    case .cursor:
      let claims = JSON.jwt(token)
      guard let subject = claims["sub"] as? String,
        let id = subject.split(separator: "|").last.map(String.init), !id.isEmpty,
        id.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
        }),
        let expiry = JSON.date(claims["exp"]), expiry > Date().addingTimeInterval(30),
        token.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
        })
      else {
        throw TrackerError.message("Open Cursor to renew sign-in")
      }
      // Derive the app's own web session from its local OAuth token. No browser store is read.
      let cookie = "WorkosCursorSessionToken=\(id)%3A%3A\(token)"
      let user = try await request("/api/auth/me", cookie: cookie)
      guard let returnedSubject = user["sub"] as? String,
        returnedSubject.split(separator: "|").last.map(String.init) == id
      else {
        throw TrackerError.message("Account changed · refresh")
      }
      let summary = try await request("/api/usage-summary", cookie: cookie)
      let shared = try? await request(
        "/api/dashboard/get-sand-usage-status", body: [:], cookie: cookie)
      return try UsageParser.cursor(summary, shared: shared)
    case .kimi:
      return try UsageParser.kimi(await request("/coding/v1/usages"))
    case .minimax:
      return try UsageParser.minimax(await request("/v1/token_plan/remains"))
    case .opencode:
      return try UsageParser.opencode(await request("/inference/go/v1/usage"))
    case .kiro:
      guard let accountID, LocalAccounts.kiroHost(profileARN: accountID) == host else {
        throw TrackerError.message("Unsupported Kiro region")
      }
      return try UsageParser.kiro(await request("/", body: ["profileArn": accountID]))
    default: throw TrackerError.message("Usage source unavailable")
    }
  }
}

extension LocalAccounts {
  public func windsurfUsage(at file: URL) throws -> UsageSnapshot {
    guard let data = LocalDatabase.value(at: file, key: "windsurf.settings.cachedPlanInfo") else {
      throw TrackerError.message("Open Devin to update usage")
    }
    let modified =
      (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? .distantPast
    return try UsageParser.windsurf(JSON.object(data), at: modified)
  }

  public func saveProviderKey(provider: Provider, name: String, token: String, host: String) throws
  {
    guard provider.acceptsKey, provider.allowedHosts.contains(host) else {
      throw TrackerError.message("Unsupported provider")
    }
    if provider == .zai {
      try saveZai(name: name, token: token, host: host)
      return
    }
    let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty, !token.contains(where: { $0.isNewline }) else {
      throw TrackerError.message("Enter a valid key")
    }
    let id = Self.providerIdentity(provider, token: token, host: host)
    try KeychainStore.write(try JSON.data(["token": token, "host": host]), account: id)
    try saveProfile(SavedProfile(id: id, provider: provider, name: name, identity: id))
  }
}
