import Foundation

public enum UsageParser {
  public static func codex(_ json: [String: Any], at date: Date = Date(), cached: Bool = false)
    -> UsageSnapshot
  {
    var windows: [UsageWindow] = []
    let rate = json["rate_limit"] as? [String: Any] ?? json
    for (key, fallback) in [("primary_window", "Session"), ("secondary_window", "Weekly")] {
      let alias = key == "primary_window" ? "primary" : "secondary"
      guard let w = (rate[key] ?? rate[alias]) as? [String: Any],
        let used = JSON.number(w["used_percent"] ?? w["usedPercent"])
      else { continue }
      let minutes =
        JSON.number(w["window_minutes"] ?? w["windowDurationMins"])
        ?? JSON.number(w["limit_window_seconds"]).map { $0 / 60 }
      let label = windowTitle(minutes, fallback: fallback)
      windows.append(
        UsageWindow(
          id: alias, title: label, usedPercent: used,
          resetsAt: JSON.date(w["reset_at"] ?? w["resets_at"] ?? w["resetsAt"])))
    }
    if let extra = json["additional_rate_limits"] as? [[String: Any]] {
      for (index, item) in extra.enumerated() {
        let name =
          item["limit_name"] as? String ?? item["metered_feature"] as? String ?? "Additional"
        var extraWindows = codex(item, at: date).windows
        for i in extraWindows.indices {
          extraWindows[i].id = "extra-\(index)-\(i)"
          extraWindows[i].title = "\(name) · \(extraWindows[i].title)"
        }
        windows += extraWindows
      }
    }
    let credits = json["credits"] as? [String: Any]
    let balance =
      credits?["unlimited"] as? Bool == true ? "Unlimited" : credits?["balance"] as? String
    return UsageSnapshot(
      windows: windows, fetchedAt: date, source: cached ? "Codex cache" : "Live",
      plan: json["plan_type"] as? String ?? json["planType"] as? String, creditBalance: balance)
  }

  public static func claude(_ json: [String: Any], at date: Date = Date()) -> UsageSnapshot {
    var windows: [UsageWindow] = []
    for (key, title) in [
      ("five_hour", "5 hours"), ("seven_day", "Weekly"), ("seven_day_opus", "Opus · weekly"),
      ("seven_day_sonnet", "Sonnet · weekly"), ("seven_day_oauth_apps", "Apps · weekly"),
    ] {
      guard let w = json[key] as? [String: Any], let p = JSON.number(w["utilization"]) else {
        continue
      }
      windows.append(
        UsageWindow(id: key, title: title, usedPercent: p, resetsAt: JSON.date(w["resets_at"])))
    }
    // Newer Claude responses expose additional scoped model limits here.
    if let limits = json["limits"] as? [[String: Any]] {
      for (i, w) in limits.enumerated() {
        guard let percent = JSON.number(w["percent"]) else { continue }
        let kind = w["kind"] as? String ?? ""
        if kind == "session" && windows.contains(where: { $0.id == "five_hour" }) { continue }
        if kind == "weekly_all" && windows.contains(where: { $0.id == "seven_day" }) { continue }
        let scope = w["scope"] as? [String: Any]
        let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
        if let model,
          windows.contains(where: { $0.title.lowercased().hasPrefix(model.lowercased()) })
        {
          continue
        }
        let title = model.map { "\($0) · weekly" } ?? (kind == "session" ? "5 hours" : "Weekly")
        windows.append(
          UsageWindow(
            id: "limit-\(i)", title: title, usedPercent: percent,
            resetsAt: JSON.date(w["resets_at"])))
      }
    }
    var spend: Spend?
    // Do not relabel monthly extra usage, credits, or rolling percentages as weekly dollars.
    if let extra = json["extra_usage"] as? [String: Any],
      let weekly = extra["weekly"] as? [String: Any],
      let amount = weekly["used"] as? [String: Any],
      let minor = JSON.number(amount["amount_minor"]),
      let exponent = JSON.number(amount["exponent"]), let currency = amount["currency"] as? String
    {
      spend = Spend(amount: minor / pow(10, exponent), currency: currency, period: "Weekly spend")
    }
    return UsageSnapshot(windows: windows, fetchedAt: date, spend: spend)
  }

  public static func zai(_ json: [String: Any], at date: Date = Date()) -> UsageSnapshot {
    let data = json["data"] as? [String: Any] ?? json
    let limits = data["limits"] as? [[String: Any]] ?? []
    let windows = limits.enumerated().compactMap { index, item -> UsageWindow? in
      let type = item["type"] as? String ?? ""
      guard ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT", "WEEKLY_LIMIT"].contains(type) else {
        return nil
      }
      let limit = JSON.number(item["usage"])
      let used =
        JSON.number(item["currentValue"])
        ?? JSON.number(item["remaining"]).flatMap { remaining in
          limit.map { max(0, $0 - remaining) }
        }
      let countPercent = used.flatMap { u in limit.flatMap { $0 > 0 ? u / $0 * 100 : nil } }
      guard let percent = countPercent ?? JSON.number(item["percentage"]) else { return nil }
      let unit = JSON.number(item["unit"])
      let count = JSON.number(item["number"])
      let minutesPerUnit: [Double: Double] = [1: 1440, 3: 60, 5: 1, 6: 10080]
      let minutes = unit.flatMap { minutesPerUnit[$0] }.flatMap { multiplier in
        count.flatMap { $0 > 0 ? $0 * multiplier : nil }
      }
      let title: String
      if type.contains("WEEK") {
        title = "Weekly"
      } else if type == "TIME_LIMIT" {
        title =
          unit == nil || (unit == 5 && count == 1)
          ? "MCP · monthly" : "MCP · \(windowTitle(minutes, fallback: "Quota"))"
      } else {
        title = windowTitle(
          minutes, fallback: unit == nil && type == "TOKENS_LIMIT" ? "5 hours" : "Quota")
      }
      var reset = JSON.date(item["nextResetTime"] ?? item["resetTime"])
      if minutes == 300, let at = reset, at.timeIntervalSince(date) > 18060 { reset = nil }
      return UsageWindow(
        id: "zai-\(index)", title: title, usedPercent: percent,
        resetsAt: reset, used: used, limit: limit,
        unit: type == "TIME_LIMIT" ? "calls" : type == "CREDIT_LIMIT" ? "credits" : nil)
    }
    let plan =
      (data["planName"] ?? data["plan"] ?? data["plan_type"] ?? data["packageName"]) as? String
    return UsageSnapshot(windows: windows, fetchedAt: date, plan: plan)
  }

  public static func windowTitle(_ minutes: Double?, fallback: String) -> String {
    guard let minutes else { return fallback }
    if minutes >= 10080 && minutes < 20160 { return "Weekly" }
    if minutes == 300 { return "5 hours" }
    if minutes >= 1440 { return "\(Int(minutes / 1440)) days" }
    if minutes >= 60 { return "\(Int(minutes / 60)) hours" }
    return "\(Int(minutes)) min"
  }
}

// Never follow redirects with provider credentials, log response bodies, or cache authentication headers.
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}

public struct UsageClient: Sendable {
  public init() {}
  public func fetch(
    provider: Provider, token: String, accountID: String? = nil, zaiHost: String = "api.z.ai",
    projectID: String? = nil, headers: [String: String] = [:]
  ) async throws -> UsageSnapshot {
    if Provider.additional.contains(provider) {
      return try await fetchCodingPlan(
        provider: provider, token: token, host: zaiHost, accountID: accountID, headers: headers)
    }
    if provider == .gemini {
      return try await fetchGemini(token: token, projectID: projectID, expectedEmail: accountID)
    }
    let url: URL
    switch provider {
    case .codex: url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    case .claude: url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    case .zai:
      guard ["api.z.ai", "open.bigmodel.cn"].contains(zaiHost) else {
        throw TrackerError.message("Unsupported Z.ai host")
      }
      url = URL(string: "https://\(zaiHost)/api/monitor/usage/quota/limit")!
    default: throw TrackerError.message("Usage source unavailable")
    }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("SubTracker/1.0", forHTTPHeaderField: "User-Agent")
    if provider == .codex, let accountID {
      request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
    }
    if provider == .claude {
      request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    }
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.timeoutIntervalForResource = 25
    let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let (body, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw TrackerError.message("No response")
    }
    switch response.statusCode {
    case 200: break
    case 401, 403: throw TrackerError.message("Sign in again")
    case 429: throw TrackerError.message("Rate limited · try later")
    default: throw TrackerError.message("Provider unavailable (\(response.statusCode))")
    }
    let json = JSON.object(body)
    let snapshot: UsageSnapshot
    switch provider {
    case .codex: snapshot = UsageParser.codex(json)
    case .claude: snapshot = UsageParser.claude(json)
    case .zai:
      if json["success"] as? Bool == false { throw TrackerError.message("Z.ai rejected this key") }
      snapshot = UsageParser.zai(json)
    default: throw TrackerError.message("Usage source unavailable")
    }
    guard !snapshot.windows.isEmpty || snapshot.creditBalance != nil else {
      throw TrackerError.message("Usage not reported")
    }
    return snapshot
  }
}
