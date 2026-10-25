import AppKit
import Combine
import SubTrackerCore

@MainActor final class TrackerStore: ObservableObject {
  @Published var accounts: [Account] = []
  @Published var refreshing = false
  @Published var refreshedAt: Date?
  @Published var notice: String?
  @Published var switching = false
  let local: LocalAccounts
  private var lastAttempts: [String: Date] = [:]
  private var retryAfter: [String: Date] = [:]
  private var cache: [String: UsageSnapshot] = [:]
  var changed: (() -> Void)?
  let demo: Bool

  init(demo: Bool = false, googleDemo: Bool = false, codingDemo: Bool = false) {
    self.demo = demo
    local = LocalAccounts()
    if !demo,
      let data = try? Data(contentsOf: local.paths.support.appendingPathComponent("usage.json")),
      let saved = try? JSONDecoder().decode([String: UsageSnapshot].self, from: data)
    {
      cache = saved
    }
    if demo {
      accounts =
        codingDemo
        ? Self.codingDemoAccounts : googleDemo ? Self.googleDemoAccounts : Self.demoAccounts
      refreshedAt = Date()
    }
  }
  var visibleAccounts: [Account] { demo ? accounts : accounts.filter(\.canDisplayUsage) }
  var menuTitle: String {
    guard UserDefaults.standard.object(forKey: "showRemaining") as? Bool ?? true else { return "" }
    let remaining = visibleAccounts.filter(\.showsInCompactView).compactMap { a -> Double? in
      guard a.issue == nil, let usage = a.usage, !usage.isStale() else { return nil }
      return usage.windows.map(\.remainingPercent).min()
    }.min()
    return remaining.map { "\(Int($0.rounded(.down)))%" } ?? ""
  }
  var footer: String {
    if refreshing { return "Updating…" }
    if !accounts.isEmpty && accounts.allSatisfy({ $0.issue != nil }) { return "Unable to update" }
    guard let refreshedAt else { return "" }
    let minutes = Int(Date().timeIntervalSince(refreshedAt) / 60)
    return minutes < 1 ? "Updated just now" : "Updated \(minutes)m ago"
  }
  func refresh() async {
    guard !refreshing, !switching, !demo else { return }
    refreshing = true
    changed?()
    defer {
      refreshing = false
      changed?()
    }
    let local = self.local
    let discovered = await Task.detached(priority: .utility) { local.discover() }.value
    let previous = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    let now = Date()
    func canAttempt(_ account: Account) -> Bool {
      if case .unavailable = account.source { return false }
      if let retry = retryAfter[account.id], retry > now { return false }
      return now.timeIntervalSince(lastAttempts[account.id] ?? .distantPast) >= 60
    }
    accounts = discovered.map { account in
      var a = account
      // Keep an in-memory reading while the refresh floor applies. Once a new
      // request is permitted, Google readings must be revalidated before display.
      let retained =
        account.canCacheUsage || !canAttempt(account)
        ? previous[account.id]?.usage : nil
      let best =
        [account.usage, retained, account.canCacheUsage ? cache[account.id] : nil].compactMap { $0 }
        .max { $0.fetchedAt < $1.fetchedAt }
      a.usage = best
      a.issue = account.issue ?? previous[account.id]?.issue
      a.retainVerification(from: previous[account.id])
      if account.provider == .antigravity, retained != nil {
        a.isActive = previous[account.id]?.isActive ?? false
      }
      return a
    }
    let eligible = accounts.filter(canAttempt)
    for account in eligible { lastAttempts[account.id] = now }
    await withTaskGroup(of: (String, UsageSnapshot?, String?).self) { group in
      for account in eligible {
        group.addTask {
          do {
            if case .windsurfCache(let file) = account.source {
              let usage = try await Task.detached(priority: .utility) {
                try local.windsurfUsage(at: file)
              }.value
              return (account.id, usage, nil)
            }
            if case .antigravityCLI(let executable) = account.source {
              let usage = try await Task.detached(priority: .utility) {
                try AntigravityUsage.fetch(executable: executable)
              }.value
              return (account.id, usage, nil)
            }
            let credentials = try await Task.detached(priority: .utility) {
              try local.credentials(for: account)
            }.value
            let usage = try await UsageClient().fetch(
              provider: account.provider, token: credentials.token,
              accountID: credentials.accountID, zaiHost: credentials.host,
              projectID: credentials.projectID, headers: credentials.headers)
            return (account.id, usage, nil)
          } catch {
            let issue = (error as? TrackerError)?.localizedDescription ?? "Connection unavailable"
            return (account.id, nil, issue)
          }
        }
      }
      for await (id, usage, issue) in group {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { continue }
        accounts[index].applyUsage(usage, issue: issue)
        if let usage {
          if accounts[index].canCacheUsage { cache[id] = usage }
          if accounts[index].provider == .antigravity { accounts[index].isActive = true }
          retryAfter[id] = nil
        }
        if issue?.contains("Rate limited") == true {
          retryAfter[id] = Date().addingTimeInterval(900)
        }
      }
    }
    if !eligible.isEmpty { refreshedAt = Date() }
    cache = cache.filter { id, _ in accounts.contains { $0.id == id && $0.canCacheUsage } }
    if let data = try? JSONEncoder().encode(cache) {
      try? PrivateFiles.write(data, to: local.paths.support.appendingPathComponent("usage.json"))
    }
  }
  func activate(_ account: Account) async {
    guard !switching, !refreshing, !demo, account.canSwitch else { return }
    switching = true
    let local = self.local
    do {
      let credentials = try await Task.detached { try local.credentials(for: account) }.value
      _ = try await UsageClient().fetch(
        provider: account.provider, token: credentials.token, accountID: credentials.accountID,
        zaiHost: credentials.host)
      try await Task.detached { try local.switchAccount(account) }.value
      notice = "\(account.name) is active. Restart running clients to reload the sign-in."
    } catch { notice = error.localizedDescription }
    switching = false
    await refresh()
  }
  func saveClaude() async {
    guard !demo else { return }
    let local = self.local
    do {
      try await Task.detached { try local.saveClaude() }.value
      notice = "Claude sign-in saved in Keychain."
    } catch { notice = error.localizedDescription }
    await refresh()
  }
  func prepareLogin(_ provider: Provider) async -> Bool {
    guard !switching, !demo else { return false }
    let local = self.local
    do {
      try await Task.detached {
        if provider == .codex { try local.saveCurrentCodex() }
        if provider == .claude,
          local.discover().contains(where: { $0.provider == .claude && $0.isActive })
        {
          try local.saveClaude()
        }
      }.value
      return true
    } catch {
      notice = error.localizedDescription
      return false
    }
  }
  func connectProvider(_ provider: Provider, name: String, token: String, host: String) async
    -> Bool
  {
    guard !demo else { return false }
    do {
      _ = try await UsageClient().fetch(
        provider: provider, token: token.trimmingCharacters(in: .whitespacesAndNewlines),
        zaiHost: host)
      let local = self.local
      try await Task.detached {
        try local.saveProviderKey(provider: provider, name: name, token: token, host: host)
      }.value
      await refresh()
      return true
    } catch {
      notice = error.localizedDescription
      return false
    }
  }
  static var codingDemoAccounts: [Account] {
    let now = Date()
    return [
      Account(
        id: "demo-copilot", provider: .copilot, name: "", isActive: true,
        usage: UsageSnapshot(
          windows: [
            UsageWindow(
              id: "premium", title: "Premium requests", usedPercent: 22,
              resetsAt: now.addingTimeInterval(3600 * 72))
          ], plan: "Pro",
          metrics: [UsageMetric(id: "completions", title: "Completions", value: "Unlimited")]),
        canSwitch: false),
      Account(
        id: "demo-cursor", provider: .cursor, name: "", isActive: true,
        usage: UsageSnapshot(windows: [
          UsageWindow(
            id: "weekly", title: "Weekly", usedPercent: 35,
            resetsAt: now.addingTimeInterval(3600 * 42))
        ]), canSwitch: false),
      Account(
        id: "demo-kimi", provider: .kimi, name: "", isActive: true,
        usage: UsageSnapshot(windows: [
          UsageWindow(
            id: "5h", title: "5 hours", usedPercent: 8, resetsAt: now.addingTimeInterval(3600 * 3)),
          UsageWindow(
            id: "monthly", title: "Monthly", usedPercent: 41,
            resetsAt: now.addingTimeInterval(3600 * 90)),
        ]), canSwitch: false),
    ]
  }
  static var googleDemoAccounts: [Account] {
    let now = Date()
    return [
      Account(
        id: "demo-gemini", provider: .gemini, name: "Work", plan: "Code Assist Standard",
        isActive: true,
        usage: UsageSnapshot(windows: [
          UsageWindow(
            id: "pro", title: "Pro", usedPercent: 25, resetsAt: now.addingTimeInterval(3600 * 8)),
          UsageWindow(
            id: "flash", title: "Flash", usedPercent: 12, resetsAt: now.addingTimeInterval(3600 * 8)
          ),
        ]), canSwitch: false),
      Account(
        id: "demo-antigravity", provider: .antigravity, name: "Local CLI", isActive: true,
        usage: UsageSnapshot(windows: [
          UsageWindow(
            id: "gemini-weekly", title: "Gemini Models · Weekly", usedPercent: 35,
            resetsAt: now.addingTimeInterval(3600 * 42)),
          UsageWindow(
            id: "claude-weekly", title: "Claude and GPT models · Weekly", usedPercent: 58,
            resetsAt: now.addingTimeInterval(3600 * 42)),
        ]), canSwitch: false),
    ]
  }
  static var demoAccounts: [Account] {
    let now = Date()
    return [
      Account(
        id: "demo-codex-a", provider: .codex, name: "Personal", plan: "pro", isActive: true,
        usage: UsageSnapshot(
          windows: [
            UsageWindow(
              id: "weekly", title: "Weekly", usedPercent: 58,
              resetsAt: now.addingTimeInterval(3600 * 42))
          ], creditBalance: "1280")),
      Account(
        id: "demo-codex-b", provider: .codex, name: "Work", plan: "pro",
        usage: UsageSnapshot(windows: [
          UsageWindow(
            id: "weekly", title: "Weekly", usedPercent: 12,
            resetsAt: now.addingTimeInterval(3600 * 51))
        ])),
      Account(
        id: "demo-claude", provider: .claude, name: "Personal", plan: "default_claude_max_20x",
        isActive: true,
        usage: UsageSnapshot(windows: [
          UsageWindow(
            id: "5h", title: "5 hours", usedPercent: 4, resetsAt: now.addingTimeInterval(3600 * 3)),
          UsageWindow(
            id: "weekly", title: "Weekly", usedPercent: 31,
            resetsAt: now.addingTimeInterval(3600 * 83)),
        ])),
      Account(
        id: "demo-zai", provider: .zai, name: "Coding Plan", plan: "max", isActive: true,
        usage: UsageSnapshot(windows: [
          UsageWindow(
            id: "5h", title: "5 hours", usedPercent: 24, resetsAt: now.addingTimeInterval(3600 * 2))
        ])),
    ]
  }
}
