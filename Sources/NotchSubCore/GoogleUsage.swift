import Foundation

extension UsageParser {
  public static func gemini(_ json: [String: Any], plan: String? = nil, at date: Date = Date())
    -> UsageSnapshot
  {
    var byModel: [String: UsageWindow] = [:]
    for bucket in json["buckets"] as? [[String: Any]] ?? [] {
      guard let model = bucket["modelId"] as? String, !model.isEmpty,
        let fraction = JSON.number(bucket["remainingFraction"]), (0...1).contains(fraction)
      else { continue }
      let title = model.replacingOccurrences(of: "gemini-", with: "")
        .replacingOccurrences(of: "-", with: " ").capitalized
      let window = UsageWindow(
        id: model, title: title, usedPercent: (1 - fraction) * 100,
        resetsAt: JSON.date(bucket["resetTime"]))
      if let existing = byModel[model], existing.usedPercent >= window.usedPercent { continue }
      byModel[model] = window
    }
    return UsageSnapshot(
      windows: byModel.values.sorted { $0.id < $1.id }, fetchedAt: date, plan: plan)
  }

  public static func geminiPlan(_ json: [String: Any]) throws -> String? {
    let paid = json["paidTier"] as? [String: Any] ?? [:]
    let current = json["currentTier"] as? [String: Any] ?? [:]
    let id = paid["id"] as? String ?? current["id"] as? String
    let unsupported = (json["ineligibleTiers"] as? [[String: Any]] ?? [])
      .contains { $0["reasonCode"] as? String == "UNSUPPORTED_CLIENT" }
    if unsupported && paid.isEmpty && (current.isEmpty || id == "free-tier" || id == "legacy-tier")
    {
      throw TrackerError.message("Use Antigravity for this plan")
    }
    if let name = paid["name"] as? String, !name.isEmpty { return name }
    if let name = current["name"] as? String, !name.isEmpty { return name }
    switch id {
    case "free-tier": return "Free"
    case "standard-tier": return "Code Assist"
    case "legacy-tier": return "Legacy"
    default: return nil
    }
  }

  public static func antigravity(_ json: [String: Any], at date: Date = Date()) throws
    -> UsageSnapshot
  {
    guard json["status"] as? String == "SUCCESS", let command = json["command"] as? [String: Any],
      command["name"] as? String == "usage", let data = command["data"] as? [String: Any]
    else {
      throw TrackerError.message("Antigravity usage unavailable")
    }
    var windows: [UsageWindow] = []
    for (groupIndex, group) in (data["groups"] as? [[String: Any]] ?? []).enumerated() {
      let groupTitle =
        (group["display_name"] ?? group["displayName"] ?? group["name"]) as? String ?? "Models"
      for bucket in group["buckets"] as? [[String: Any]] ?? [] {
        guard bucket["disabled"] as? Bool != true,
          let id = (bucket["bucket_id"] ?? bucket["bucketId"] ?? bucket["id"]) as? String,
          !id.isEmpty
        else { continue }
        let nested = bucket["remaining"] as? [String: Any] ?? [:]
        let oneof =
          ["remainingFraction", "remaining_fraction"].contains(nested["case"] as? String ?? "")
          ? nested["value"] : nil
        guard
          let fraction = JSON.number(
            bucket["remaining_fraction"] ?? bucket["remainingFraction"] ?? nested[
              "remaining_fraction"] ?? nested["remainingFraction"] ?? oneof),
          (0...1).contains(fraction)
        else { continue }
        let name =
          (bucket["display_name"] ?? bucket["displayName"] ?? bucket["name"]) as? String ?? id
        windows.append(
          UsageWindow(
            id: "\(groupIndex)-\(id)", title: "\(groupTitle) · \(name)",
            usedPercent: (1 - fraction) * 100,
            resetsAt: JSON.date(bucket["reset_time"] ?? bucket["resetTime"])))
      }
    }
    guard !windows.isEmpty else { throw TrackerError.message("Usage not reported") }
    return UsageSnapshot(windows: windows, fetchedAt: date)
  }
}

extension UsageClient {
  func fetchGemini(token: String, projectID: String?, expectedEmail: String? = nil) async throws
    -> UsageSnapshot
  {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.timeoutIntervalForResource = 25
    let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    func request(_ url: String, body: [String: Any]? = nil) async throws -> [String: Any] {
      var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("NotchSub", forHTTPHeaderField: "User-Agent")
      if let body {
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSON.data(body)
      }
      let (data, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else {
        throw TrackerError.message("No response")
      }
      switch response.statusCode {
      case 200: return JSON.object(data)
      case 401: throw TrackerError.message("Open Gemini CLI to renew sign-in")
      case 403: throw TrackerError.message("Gemini quota access unavailable")
      case 429: throw TrackerError.message("Rate limited · try later")
      default: throw TrackerError.message("Provider unavailable (\(response.statusCode))")
      }
    }
    // Verify identity before attributing a keychain credential to cached account metadata.
    if let expectedEmail {
      let user = try await request("https://www.googleapis.com/oauth2/v2/userinfo")
      guard (user["email"] as? String)?.lowercased() == expectedEmail.lowercased() else {
        throw TrackerError.message("Account changed · refresh")
      }
    }
    var setup: [String: Any] = ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]]
    if let projectID { setup["cloudaicompanionProject"] = projectID }
    let info = try await request(
      "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist", body: setup)
    let plan = try UsageParser.geminiPlan(info)
    let project = info["cloudaicompanionProject"] as? String ?? projectID
    guard let project, !project.isEmpty else {
      throw TrackerError.message("Set the project in Gemini CLI")
    }
    let quota = try await request(
      "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota", body: ["project": project]
    )
    let result = UsageParser.gemini(quota, plan: plan)
    guard !result.windows.isEmpty else { throw TrackerError.message("Usage not reported") }
    return result
  }
}
