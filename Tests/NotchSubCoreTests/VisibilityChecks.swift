import Foundation
import NotchSubCore

extension NotchSubCoreTests {
  static var visibilityChecks: [(String, (NotchSubCoreTests) throws -> Void)] {
    [
      ("Discovery and caches do not validate accounts", { $0.testUnverifiedAccountsStayHidden() }),
      (
        "Failed validation hides accounts until recovery", { $0.testVisibilityFailureAndRecovery() }
      ),
      (
        "Verification survives only the same discovered account", { $0.testVerificationRetention() }
      ),
      (
        "Installed apps without credentials do not add providers",
        { try $0.testInstalledAppIsNotAccount() }
      ),
    ]
  }

  func testUnverifiedAccountsStayHidden() {
    let usage = UsageSnapshot(windows: [
      UsageWindow(id: "weekly", title: "Weekly", usedPercent: 100)
    ])
    var account = Account(
      id: "one", provider: .codex, name: "", isActive: true,
      source: .codex(root.appendingPathComponent("auth.json")), usage: usage)
    expect(!account.canDisplayUsage)
    account.applyUsage(usage, issue: nil)
    expect(account.canDisplayUsage)  // An exhausted allowance is still a valid account.

    var installedCLI = Account(
      id: "agy", provider: .antigravity, name: "",
      source: .antigravityCLI(root.appendingPathComponent("agy")))
    expect(!installedCLI.canDisplayUsage)
    installedCLI.applyUsage(usage, issue: nil)
    expect(installedCLI.canDisplayUsage)

    for source in [
      AuthSource.unavailable, .windsurfCache(root.appendingPathComponent("state.vscdb")),
    ] {
      var cacheOnly = Account(
        id: "cache", provider: .windsurf, name: "", source: source, usage: usage)
      cacheOnly.applyUsage(usage, issue: nil)
      expect(!cacheOnly.canDisplayUsage)
    }
    var cached = usage
    cached.source = "Codex cache"
    account.applyUsage(cached, issue: nil)
    expect(!account.canDisplayUsage)
  }

  func testVisibilityFailureAndRecovery() {
    let usage = UsageSnapshot(windows: [UsageWindow(id: "weekly", title: "Weekly", usedPercent: 20)]
    )
    var account = Account(id: "one", provider: .kimi, name: "", source: .additionalLocal)
    account.applyUsage(usage, issue: nil)
    expect(account.canDisplayUsage)
    for issue in [
      "Sign in again", "Account changed · refresh", "Rate limited · try later",
      "Connection unavailable",
    ] {
      account.applyUsage(nil, issue: issue)
      expect(!account.canDisplayUsage)
      expectNotNil(account.usage)  // Keeping a cache must not bypass the gate.
      account.applyUsage(usage, issue: nil)
      expect(account.canDisplayUsage)
    }
    account.applyUsage(nil, issue: nil)
    expect(!account.canDisplayUsage)
  }

  func testVerificationRetention() {
    let usage = UsageSnapshot(windows: [UsageWindow(id: "weekly", title: "Weekly", usedPercent: 50)]
    )
    var previous = Account(id: "one", provider: .cursor, name: "", source: .additionalLocal)
    previous.applyUsage(usage, issue: nil)
    var discovered = Account(
      id: "one", provider: .cursor, name: "", source: .additionalLocal, usage: usage)
    discovered.retainVerification(from: previous)
    expect(discovered.canDisplayUsage)
    discovered.issue = "Open Cursor to renew sign-in"
    discovered.retainVerification(from: previous)
    expect(!discovered.canDisplayUsage)
    discovered.issue = nil
    discovered.id = "two"
    discovered.retainVerification(from: previous)
    expect(!discovered.canDisplayUsage)
    discovered.id = "one"
    discovered.source = .vault("one")
    discovered.retainVerification(from: previous)
    expect(!discovered.canDisplayUsage)
    discovered.source = .additionalLocal
    discovered.retainVerification(from: nil)
    expect(!discovered.canDisplayUsage)  // A restart must revalidate, even with a disk cache.
    expectEqual([previous, discovered].filter(\.canDisplayUsage).count, 1)
  }

  func testInstalledAppIsNotAccount() throws {
    try PrivateFiles.directory(root.appendingPathComponent(".zcode"))
    try write(JSON.data(["oauthAccount": ["accountUuid": "leftover-metadata"]]), ".claude.json")
    let candidates = local.discover()
    expect(!candidates.contains { $0.provider == .zai })
    expect(candidates.filter(\.canDisplayUsage).isEmpty)
  }
}
