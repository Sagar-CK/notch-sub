import CoreFoundation
import Foundation

public enum Provider: String, CaseIterable, Codable, Sendable, Identifiable {
  case codex, claude, zai, gemini, antigravity, copilot, cursor, kimi, minimax, windsurf, kiro,
    opencode
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .codex: "Codex"
    case .claude: "Claude"
    case .zai: "Z.ai"
    case .gemini: "Gemini"
    case .antigravity: "Antigravity"
    case .copilot: "Copilot"
    case .cursor: "Cursor"
    case .kimi: "Kimi"
    case .minimax: "MiniMax"
    case .windsurf: "Devin"
    case .kiro: "Kiro"
    case .opencode: "OpenCode Go"
    }
  }
  public var dashboard: URL {
    let value =
      switch self {
      case .codex: "https://chatgpt.com/codex/settings/usage"
      case .claude: "https://claude.ai/settings/usage"
      case .zai: "https://z.ai/manage-apikey/coding-plan/personal/my-plan"
      case .gemini: "https://geminicli.com/docs/resources/quota-and-pricing/"
      case .antigravity: "https://antigravity.google/"
      case .copilot: "https://github.com/settings/copilot"
      case .cursor: "https://cursor.com/dashboard?tab=usage"
      case .kimi: "https://www.kimi.com/code/console"
      case .minimax: "https://www.minimax.io/m-plan"
      case .windsurf: "https://app.devin.ai/"
      case .kiro: "https://app.kiro.dev/"
      case .opencode: "https://opencode.ai/console"
      }
    return URL(string: value)!
  }
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var usedPercent: Double
  public var resetsAt: Date?
  public var used: Double?
  public var limit: Double?
  public var unit: String?
  public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
  public init(
    id: String, title: String, usedPercent: Double, resetsAt: Date? = nil, used: Double? = nil,
    limit: Double? = nil, unit: String? = nil
  ) {
    self.id = id
    self.title = title
    self.usedPercent = max(0, usedPercent)
    self.resetsAt = resetsAt
    self.used = used
    self.limit = limit
    self.unit = unit
  }
  public func hasReset(at now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }
}

public struct Spend: Codable, Equatable, Sendable {
  public var amount: Double
  public var currency: String
  public var period: String
  public init(amount: Double, currency: String, period: String) {
    self.amount = amount
    self.currency = currency
    self.period = period
  }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
  public var windows: [UsageWindow]
  public var fetchedAt: Date
  public var source: String
  public var plan: String?
  public var creditBalance: String?
  public var spend: Spend?
  public var metrics: [UsageMetric]?
  public init(
    windows: [UsageWindow] = [], fetchedAt: Date = Date(), source: String = "Live",
    plan: String? = nil, creditBalance: String? = nil, spend: Spend? = nil,
    metrics: [UsageMetric] = []
  ) {
    self.windows = windows
    self.fetchedAt = fetchedAt
    self.source = source
    self.plan = plan
    self.creditBalance = creditBalance
    self.spend = spend
    self.metrics = metrics
  }
  public func isStale(at now: Date = Date()) -> Bool {
    source == "Local cache" || now.timeIntervalSince(fetchedAt) > 900
      || windows.contains { $0.hasReset(at: now) }
  }
}

public struct UsageMetric: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var value: String
  public init(id: String, title: String, value: String) {
    self.id = id
    self.title = title
    self.value = value
  }
}

public enum AuthSource: Equatable, Sendable {
  case codex(URL)
  case claudeLocal
  case vault(String)
  case zaiSettings(URL)
  case zaiEnvironment
  case geminiFile(URL)
  case geminiKeychain
  case antigravityCLI(URL)
  case additionalLocal
  case windsurfCache(URL)
  case unavailable
}

public struct Account: Identifiable, Equatable, Sendable {
  public var id: String
  public var provider: Provider
  public var name: String
  public var email: String?
  public var plan: String?
  public var isActive: Bool
  public var source: AuthSource
  public var canSwitch: Bool
  public var usage: UsageSnapshot?
  public var issue: String?
  public init(
    id: String, provider: Provider, name: String, email: String? = nil, plan: String? = nil,
    isActive: Bool = false, source: AuthSource = .unavailable, usage: UsageSnapshot? = nil,
    issue: String? = nil, canSwitch: Bool = true
  ) {
    self.id = id
    self.provider = provider
    self.name = name
    self.email = email
    self.plan = plan
    self.isActive = isActive
    self.source = source
    self.usage = usage
    self.issue = issue
    self.canSwitch = canSwitch
  }
  public var showsInCompactView: Bool {
    if isActive { return true }
    if case .vault = source { return provider.acceptsKey && !canSwitch }
    return false
  }
  public var planLabel: String? {
    let value = usage?.plan.flatMap { $0 == "unknown" ? nil : $0 } ?? plan
    switch value?.lowercased() {
    case nil, "", "unknown": return nil
    case "promax": return "Pro Max"
    case "default_claude_max_20x": return "Max 20×"
    case "default_claude_max_5x": return "Max 5×"
    default: return value?.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
  // Google CLI metadata can lag an external account change. Revalidate each refresh;
  // the Antigravity report does not provide an identity at all.
  public var canCacheUsage: Bool { ![.gemini, .antigravity, .windsurf].contains(provider) }
}

public enum TrackerError: LocalizedError {
  case message(String)
  public var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}

public enum JSON {
  public static func object(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
  }
  public static func read(_ url: URL) -> [String: Any] {
    (try? Data(contentsOf: url)).map(object) ?? [:]
  }
  public static func data(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  }
  public static func number(_ value: Any?) -> Double? {
    if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
      return n.doubleValue.isFinite ? n.doubleValue : nil
    }
    if let s = value as? String, let d = Double(s), d.isFinite { return d }
    return nil
  }
  public static func date(_ value: Any?) -> Date? {
    if let n = number(value) { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
    guard let s = value as? String else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
  }
  public static func jwt(_ token: String?) -> [String: Any] {
    guard let parts = token?.split(separator: "."), parts.count >= 2 else { return [:] }
    var s = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    s += String(repeating: "=", count: (4 - s.count % 4) % 4)
    return Data(base64Encoded: s).map(object) ?? [:]
  }
}
