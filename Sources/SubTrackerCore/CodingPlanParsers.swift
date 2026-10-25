import Foundation

extension UsageParser {
  static func countWindow(
    id: String, title: String, used: Any?, limit: Any?, reset: Date?, unit: String? = nil
  ) -> UsageWindow? {
    guard let used = JSON.number(used), used >= 0, let limit = JSON.number(limit), limit > 0 else {
      return nil
    }
    let percent = used / limit * 100
    guard percent.isFinite else { return nil }
    return UsageWindow(
      id: id, title: title, usedPercent: percent, resetsAt: reset, used: used,
      limit: limit, unit: unit)
  }
  static func percentWindow(
    id: String, title: String, percent: Any?, reset: Date?, remaining: Bool = false
  ) -> UsageWindow? {
    guard let value = JSON.number(percent), value >= 0, !remaining || value <= 100 else {
      return nil
    }
    return UsageWindow(
      id: id, title: title, usedPercent: remaining ? 100 - value : value, resetsAt: reset)
  }
  static func requireQuota(_ snapshot: UsageSnapshot) throws -> UsageSnapshot {
    guard
      !snapshot.windows.isEmpty || snapshot.creditBalance != nil
        || snapshot.metrics?.isEmpty == false
    else {
      throw TrackerError.message("Usage not reported")
    }
    return snapshot
  }

  public static func copilot(_ json: [String: Any], at now: Date = Date()) throws -> UsageSnapshot {
    let quotas = json["quota_snapshots"] as? [String: Any] ?? [:]
    let rawReset = json["quota_reset_date"] as? String
    let reset = JSON.date(rawReset) ?? rawReset.flatMap { JSON.date($0 + "T00:00:00Z") }
    let tokenBased = json["token_based_billing"] as? Bool == true
    var windows: [UsageWindow] = []
    var metrics: [UsageMetric] = []
    var credits: Double?
    for (key, title) in [
      ("premium_interactions", "Premium requests"), ("chat", "Chat"),
      ("completions", "Completions"),
    ] {
      guard let quota = quotas[key] as? [String: Any] else { continue }
      if credits == nil { credits = JSON.number(quota["credits_used"]) }
      let unlimited = quota["unlimited"] as? Bool == true || JSON.number(quota["entitlement"]) == -1
      if unlimited {
        // Token-billed Business accounts can have unlimited legacy request placeholders.
        if !tokenBased { metrics.append(UsageMetric(id: key, title: title, value: "Unlimited")) }
        continue
      }
      guard !tokenBased, let entitlement = JSON.number(quota["entitlement"]), entitlement > 0 else {
        continue
      }
      if let window = percentWindow(
        id: key, title: title, percent: quota["percent_remaining"], reset: reset, remaining: true)
      {
        windows.append(window)
      } else if let remaining = JSON.number(quota["remaining"]), remaining >= 0 {
        if let window = countWindow(
          id: key, title: title, used: max(0, entitlement - remaining), limit: entitlement,
          reset: reset, unit: "requests")
        {
          windows.append(window)
        }
      }
    }
    if let credits, credits >= 0, tokenBased || credits > 0 {
      metrics.append(
        UsageMetric(
          id: "credits-used", title: "AI credits used",
          value: credits.formatted(.number.precision(.fractionLength(0...2)))))
      metrics.append(UsageMetric(id: "credit-limit", title: "Credit limit", value: "Not reported"))
    } else if tokenBased {
      metrics.append(UsageMetric(id: "credits", title: "AI credits", value: "Not reported"))
    }
    return try requireQuota(
      UsageSnapshot(
        windows: windows, fetchedAt: now, plan: json["copilot_plan"] as? String, metrics: metrics))
  }

  public static func cursor(
    _ json: [String: Any], shared: [String: Any]? = nil, at now: Date = Date()
  ) throws -> UsageSnapshot {
    var windows: [UsageWindow] = []
    var metrics: [UsageMetric] = []
    let reset = JSON.date(json["billingCycleEnd"])
    let individual = json["individualUsage"] as? [String: Any] ?? [:]
    let plan = individual["plan"] as? [String: Any] ?? [:]
    let unified =
      shared?["isUnified"] as? Bool == true
      || ((json["membershipType"] as? String)?.lowercased().hasPrefix("unified_") == true
        && (json["limitType"] as? String)?.lowercased() == "user")
    if unified {
      // Unified memberships have a weekly pool. Never substitute obsolete monthly pools.
      if let shared, shared["includedLimitZero"] as? Bool != true,
        shared["hasNonZeroIncludedLimit"] as? Bool == true
          || shared["includedLimitZero"] as? Bool == false,
        let window = percentWindow(
          id: "weekly", title: "Weekly", percent: shared["usagePercent"],
          reset: JSON.date(shared["nextResetTimestampUtc"]))
      {
        windows.append(window)
      }
    } else if plan["enabled"] as? Bool != false {
      for (key, title) in [
        ("autoPercentUsed", "Cursor models"), ("apiPercentUsed", "Other models"),
      ] {
        if let window = percentWindow(id: key, title: title, percent: plan[key], reset: reset) {
          windows.append(window)
        }
      }
      if windows.isEmpty {
        let window =
          percentWindow(
            id: "included", title: "Included usage", percent: plan["totalPercentUsed"], reset: reset
          )
          ?? countWindow(
            id: "included", title: "Included usage", used: plan["used"], limit: plan["limit"],
            reset: reset)
        if let window { windows.append(window) }
      }
      if windows.isEmpty {
        let overall = individual["overall"] as? [String: Any] ?? [:]
        let team = (json["teamUsage"] as? [String: Any])?["pooled"] as? [String: Any] ?? [:]
        if let personal = countWindow(
          id: "personal", title: "Personal allowance", used: overall["used"],
          limit: overall["limit"], reset: reset)
        {
          windows.append(personal)
        } else if let pooled = countWindow(
          id: "team", title: "Team pool", used: team["used"], limit: team["limit"], reset: reset)
        {
          windows.append(pooled)
        }
      }
    }
    // Raw usage-summary amounts are cents. Only render ratios here, not monthly bills or estimates.
    windows = windows.map { window in
      var value = window
      value.used = nil
      value.limit = nil
      return value
    }
    if windows.isEmpty, !unified, json["isUnlimited"] as? Bool == true {
      metrics.append(UsageMetric(id: "included", title: "Included usage", value: "Unlimited"))
    }
    return try requireQuota(
      UsageSnapshot(
        windows: windows, fetchedAt: now, plan: json["membershipType"] as? String, metrics: metrics)
    )
  }

  public static func kimi(_ json: [String: Any], at now: Date = Date()) throws -> UsageSnapshot {
    var windows: [UsageWindow] = []
    let names = [
      "limit5h": "5 hours", "limit7d": "Weekly", "monthTotal": "Monthly",
      "monthCode": "Coding · monthly",
      "limit_5h": "5 hours", "limit_7d": "Weekly", "limit_month_total": "Monthly",
      "limit_month_code": "Coding · monthly",
    ]
    var current: [(String, [String: Any])] = []
    if let entries = json["usages"] as? [[String: Any]] {
      current = entries.compactMap { item in
        guard let name = (item["scope"] ?? item["type"] ?? item["name"]) as? String else {
          return nil
        }
        return (name, item)
      }
    } else if let entries = json["usages"] as? [String: [String: Any]] {
      current = entries.map { ($0.key, $0.value) }
    }
    for (key, item) in current.sorted(by: { $0.0 < $1.0 }) {
      guard let title = names[key],
        let ratio = JSON.number(item["used_ratio"] ?? item["usedRatio"]), ratio >= 0,
        (ratio * 100).isFinite,
        !windows.contains(where: { $0.title == title })
      else { continue }
      windows.append(
        UsageWindow(
          id: key, title: title, usedPercent: ratio * 100,
          resetsAt: JSON.date(item["reset_time"] ?? item["resetAt"])))
    }
    if windows.isEmpty {
      func append(_ value: [String: Any], id: String, title: String) {
        let limit = JSON.number(value["limit"])
        let used =
          JSON.number(value["used"])
          ?? JSON.number(value["remaining"]).flatMap { remaining in limit.map { $0 - remaining } }
        if let window = countWindow(
          id: id, title: title, used: used, limit: limit,
          reset: JSON.date(value["resetTime"] ?? value["resetAt"] ?? value["reset_at"]),
          unit: "requests")
        {
          windows.append(window)
        }
      }
      if let usage = json["usage"] as? [String: Any] {
        append(usage, id: "weekly", title: "Weekly")
      }
      for (index, item) in (json["limits"] as? [[String: Any]] ?? []).enumerated() {
        let window = item["window"] as? [String: Any] ?? [:]
        let duration = JSON.number(window["duration"])
        let unit = window["timeUnit"] as? String ?? ""
        let minutes = duration.map {
          unit.contains("MINUTE")
            ? $0 : unit.contains("HOUR") ? $0 * 60 : unit.contains("DAY") ? $0 * 1440 : $0 / 60
        }
        append(
          item["detail"] as? [String: Any] ?? item, id: "limit-\(index)",
          title: windowTitle(minutes, fallback: "Quota"))
      }
    }
    let plan =
      (json["membership"] as? [String: Any])?["name"] as? String ?? json["planName"] as? String
    return try requireQuota(UsageSnapshot(windows: windows, fetchedAt: now, plan: plan))
  }

  public static func minimax(_ json: [String: Any], at now: Date = Date()) throws -> UsageSnapshot {
    let data = json["data"] as? [String: Any] ?? json
    let status = (json["base_resp"] ?? data["base_resp"]) as? [String: Any] ?? [:]
    if let code = JSON.number(status["status_code"]), code != 0 {
      throw TrackerError.message("MiniMax subscription key rejected")
    }
    var windows: [UsageWindow] = []
    var metrics: [UsageMetric] = []
    for (index, service) in (data["services"] as? [[String: Any]] ?? []).enumerated() {
      guard let name = service["service_type"] as? String,
        let period = service["window_type"] as? String
      else { continue }
      // Only explicit timestamps are used. A locale-specific time range is not a reliable reset.
      let reset = JSON.date(service["reset_at"] ?? service["end_time"])
      if let window = countWindow(
        id: "service-\(index)", title: "\(name) · \(period)",
        used: service["usage"], limit: service["limit"], reset: reset)
      {
        windows.append(window)
      }
    }
    let models = data["model_remains"] as? [[String: Any]] ?? []
    // New plans use a shared general pool; do not duplicate it for every model.
    let general = models.filter { ($0["model_name"] as? String)?.lowercased() == "general" }
    let selected =
      general.isEmpty
      ? models.filter {
        let name = ($0["model_name"] as? String)?.lowercased() ?? ""
        return name.contains("minimax-m") || name == "text" || name == "text-generation"
      } : general
    for (index, model) in (windows.isEmpty ? selected : []).enumerated() {
      for (prefix, title, resetKey, durationKey) in [
        ("current_interval", "5 hours", "end_time", "remains_time"),
        ("current_weekly", "Weekly", "weekly_end_time", "weekly_remains_time"),
      ] {
        let status = JSON.number(model[prefix + "_status"])
        let percent = JSON.number(model[prefix + "_remaining_percent"])
        let limit = JSON.number(model[prefix + "_total_count"])
        let remaining = JSON.number(model[prefix + "_usage_count"])
        let reset =
          JSON.date(model[resetKey])
          ?? JSON.number(model[durationKey]).flatMap {
            $0 > 0 ? now.addingTimeInterval($0 / 1000) : nil
          }
        // Status 3 denotes an excluded window. Zero percent with a real limit is still exhausted.
        if status == 3 { continue }
        let id = "\(index)-\(prefix)"
        let label =
          selected.count > 1 ? "\(model["model_name"] as? String ?? "Model") · \(title)" : title
        if let limit, limit > 0, let remaining, remaining >= 0,
          let window = countWindow(
            id: id, title: label, used: max(0, limit - remaining), limit: limit, reset: reset)
        {
          windows.append(window)
        } else if let window = percentWindow(
          id: id, title: label, percent: percent, reset: reset, remaining: true)
        {
          windows.append(window)
        }
      }
    }
    if let points = JSON.number(data["points_balance"]), points >= 0 {
      metrics.append(UsageMetric(id: "credits", title: "Credits", value: points.formatted()))
    }
    let plan =
      (data["current_subscribe_title"] ?? data["plan_name"] ?? data["current_plan_title"])
      as? String
    return try requireQuota(
      UsageSnapshot(windows: windows, fetchedAt: now, plan: plan, metrics: metrics))
  }

  public static func opencode(_ json: [String: Any], at now: Date = Date()) throws -> UsageSnapshot
  {
    let usage = json["usage"] as? [String: Any] ?? [:]
    var windows: [UsageWindow] = []
    for (key, title) in [("rolling", "5 hours"), ("weekly", "Weekly"), ("monthly", "Monthly")] {
      guard let item = usage[key] as? [String: Any] else { continue }
      let reset =
        JSON.date(item["resetAt"] ?? item["resetsAt"])
        ?? JSON.number(item["resetInSec"]).flatMap { $0 >= 0 ? now.addingTimeInterval($0) : nil }
      let window =
        percentWindow(
          id: key, title: title, percent: item["percent"] ?? item["usagePercent"], reset: reset)
        ?? countWindow(
          id: key, title: title, used: item["used"], limit: item["limit"], reset: reset)
      if let window { windows.append(window) }
    }
    // Monetary model-pool counters are not bills, and their units are not assumed here.
    windows = windows.map {
      var window = $0
      window.used = nil
      window.limit = nil
      return window
    }
    return try requireQuota(
      UsageSnapshot(windows: windows, fetchedAt: now, plan: json["plan"] as? String))
  }

  public static func kiro(_ json: [String: Any], at now: Date = Date()) throws -> UsageSnapshot {
    let credits = (json["usageBreakdownList"] as? [[String: Any]] ?? []).filter {
      $0["resourceType"] as? String == "CREDIT"
    }
    guard credits.count == 1, let value = credits.first else {
      throw TrackerError.message("Usage not reported")
    }
    var windows: [UsageWindow] = []
    let reset = JSON.date(value["nextDateReset"] ?? json["nextDateReset"])
    let total = JSON.number(value["currentUsageWithPrecision"] ?? value["currentUsage"])
    let overage =
      JSON.number(value["currentOveragesWithPrecision"] ?? value["currentOverages"]) ?? 0
    let limit = JSON.number(value["usageLimitWithPrecision"] ?? value["usageLimit"])
    var metrics: [UsageMetric] = []
    if let total, total >= overage, overage >= 0, (value["bonuses"] as? [Any] ?? []).isEmpty,
      let window = countWindow(
        id: "plan", title: "Plan credits", used: total - overage, limit: limit, reset: reset,
        unit: "credits")
    {
      windows.append(window)
    }
    if let total, total >= 0, !(value["bonuses"] as? [Any] ?? []).isEmpty {
      metrics.append(
        UsageMetric(
          id: "total", title: "Credits used",
          value: total.formatted(.number.precision(.fractionLength(0...2)))))
      metrics.append(UsageMetric(id: "limit", title: "Plan + bonus limit", value: "Not reported"))
    }
    if let trial = value["freeTrialInfo"] as? [String: Any],
      trial["freeTrialStatus"] as? String == "ACTIVE",
      let window = countWindow(
        id: "trial", title: "Trial credits",
        used: trial["currentUsageWithPrecision"] ?? trial["currentUsage"],
        limit: trial["usageLimitWithPrecision"] ?? trial["usageLimit"],
        reset: JSON.date(trial["freeTrialExpiry"]), unit: "credits")
    {
      windows.append(window)
    }
    if (json["overageConfiguration"] as? [String: Any])?["overageStatus"] as? String == "ENABLED",
      let window = countWindow(
        id: "overage", title: "Overage credits", used: overage,
        limit: value["overageCapWithPrecision"], reset: reset, unit: "credits")
    {
      windows.append(window)
    }
    let plan = (json["subscriptionInfo"] as? [String: Any])?["subscriptionTitle"] as? String
    return try requireQuota(
      UsageSnapshot(windows: windows, fetchedAt: now, plan: plan, metrics: metrics))
  }

  public static func windsurf(_ json: [String: Any], at date: Date) throws -> UsageSnapshot {
    var windows: [UsageWindow] = []
    let quota = json["quotaUsage"] as? [String: Any] ?? [:]
    for (key, title) in [("daily", "Daily"), ("weekly", "Weekly")] {
      if let window = percentWindow(
        id: key, title: title, percent: quota[key + "RemainingPercent"],
        reset: JSON.date(quota[key + "ResetAtUnix"]), remaining: true)
      {
        windows.append(window)
      }
    }
    if windows.isEmpty, let usage = json["usage"] as? [String: Any] {
      for (id, title, usedKey, limitKey) in [
        ("messages", "Messages", "usedMessages", "messages"),
        ("actions", "Flow actions", "usedFlowActions", "flowActions"),
      ] {
        if let window = countWindow(
          id: id, title: title, used: usage[usedKey], limit: usage[limitKey],
          reset: JSON.date(json["endTimestamp"]))
        {
          windows.append(window)
        }
      }
    }
    return try requireQuota(
      UsageSnapshot(
        windows: windows, fetchedAt: date, source: "Local cache", plan: json["planName"] as? String)
    )
  }
}
