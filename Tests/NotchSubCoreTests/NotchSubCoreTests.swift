import Foundation
import NotchSubCore

final class NotchSubCoreTests {
  var root: URL!
  var local: LocalAccounts!
  func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "notch-sub-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    local = LocalAccounts(paths: LocalPaths(home: root, environment: [:]))
  }
  func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
  func auth(
    _ account: String, user: String = "test-user", token: String = "fake-access",
    refresh: String = "2026-10-20T10:00:00Z"
  ) throws -> Data {
    let payload: [String: Any] = [
      "email": "\(account)@example.test", "sub": user,
      "https://api.openai.com/auth": ["chatgpt_user_id": user, "chatgpt_plan_type": "pro"],
    ]
    let jwt = try JSON.data(payload).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return try JSON.data([
      "tokens": [
        "account_id": account, "access_token": token, "id_token": "header.\(jwt).signature",
        "refresh_token": "fake-refresh-\(token)",
      ], "last_refresh": refresh,
    ])
  }
  func write(_ data: Data, _ relative: String) throws {
    try PrivateFiles.write(data, to: root.appendingPathComponent(relative))
  }

  func testCodexWeeklyPrimaryAndCreditsAreNotDollars() {
    let snapshot = UsageParser.codex([
      "plan_type": "promax",
      "rate_limit": [
        "primary_window": [
          "used_percent": 58, "limit_window_seconds": 604800, "reset_at": 1_793_382_159,
        ]
      ], "credits": ["balance": "63214.356"],
    ])
    expectEqual(snapshot.windows.first?.title, "Weekly")
    expectEqual(snapshot.windows.first?.remainingPercent, 42)
    expectEqual(snapshot.creditBalance, "63214.356")
    expectNil(snapshot.spend)
  }
  func testClaudeSupportsLegacyAndScopedWindowsWithoutDuplicates() {
    let snapshot = UsageParser.claude([
      "five_hour": ["utilization": 4, "resets_at": "2026-10-25T04:50:00.247915+00:00"],
      "seven_day": ["utilization": 31],
      "limits": [
        ["kind": "session", "percent": 4], ["kind": "weekly_all", "percent": 31],
        ["kind": "weekly_scoped", "percent": 12, "scope": ["model": ["display_name": "Fable"]]],
      ],
    ])
    expectEqual(snapshot.windows.count, 3)
    expectEqual(snapshot.windows.first?.remainingPercent, 96)
    expectNotNil(snapshot.windows.first?.resetsAt)
    expectEqual(snapshot.windows.last?.title, "Fable · weekly")
  }
  func testMonthlyExtraUsageNeverMasqueradesAsWeeklySpend() {
    let snapshot = UsageParser.claude([
      "extra_usage": [
        "is_enabled": true, "used_credits": 4300, "currency": "USD", "monthly_limit": 10000,
      ], "spend": ["used": ["amount_minor": 4300, "currency": "USD", "exponent": 2]],
    ])
    expectNil(snapshot.spend)
    let weekly = UsageParser.claude([
      "extra_usage": ["weekly": ["used": ["amount_minor": 1234, "currency": "USD", "exponent": 2]]]
    ])
    expectEqual(weekly.spend?.amount, 12.34)
  }
  func testZaiParsesPercentageAndMCPCounts() {
    let snapshot = UsageParser.zai([
      "data": [
        "limits": [
          ["type": "TOKENS_LIMIT", "percentage": 24],
          ["type": "TIME_LIMIT", "currentValue": 30, "usage": 100],
          ["type": "WEEKLY_LIMIT", "percentage": 10],
        ]
      ]
    ])
    expectEqual(snapshot.windows.map(\.remainingPercent), [76, 70, 90])
    expectEqual(snapshot.windows[1].unit, "calls")
    expectEqual(snapshot.windows[2].title, "Weekly")
  }
  func testExpiredWindowIsStaleAndOverageIsClamped() {
    let now = Date()
    let window = UsageWindow(
      id: "test", title: "Weekly", usedPercent: 130, resetsAt: now.addingTimeInterval(-1))
    expectEqual(window.remainingPercent, 0)
    expect(UsageSnapshot(windows: [window], fetchedAt: now).isStale(at: now))
    expect(UsageSnapshot(fetchedAt: now.addingTimeInterval(-901)).isStale(at: now))
  }
  func testZaiCreditWeeklyWindowsAndUnknownTypes() {
    let snapshot = UsageParser.zai([
      "data": [
        "planName": "Max",
        "limits": [
          [
            "type": "CREDIT_LIMIT", "unit": 3, "number": 5, "percentage": 0, "currentValue": 50,
            "usage": 200,
          ],
          [
            "type": "CREDIT_LIMIT", "unit": 6, "number": 1, "percentage": 0, "remaining": 80,
            "usage": 100,
          ],
          ["type": "UNRECOGNIZED", "percentage": 100],
        ],
      ]
    ])
    expectEqual(snapshot.windows.map(\.title), ["5 hours", "Weekly"])
    expectEqual(snapshot.windows.map(\.remainingPercent), [75, 80])
    expectEqual(snapshot.plan, "Max")
    expectNil(snapshot.spend)
  }
  func testChangedZaiKeyCannotBeFetchedUnderOldAccount() throws {
    try write(
      JSON.data([
        "env": [
          "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
          "ANTHROPIC_AUTH_TOKEN": "synthetic-one",
        ]
      ]), ".claude/settings.json")
    let account = try unwrap(local.discover().first { $0.provider == .zai })
    try write(
      JSON.data([
        "env": [
          "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
          "ANTHROPIC_AUTH_TOKEN": "synthetic-two",
        ]
      ]), ".claude/settings.json")
    expectThrows(try local.credentials(for: account))
  }
  func testDiscoveryDeduplicatesProfilesAndUsesLiveCredential() throws {
    try write(auth("one", token: "live"), ".codex/auth.json")
    try write(auth("one", token: "stale"), ".codex/accounts/one.auth.json")
    try write(
      auth("one", token: "even-newer", refresh: "2026-10-24T00:00:00Z"),
      ".codex-swap/accounts/one.auth.json")
    try write(auth("two"), ".codex/accounts/two.auth.json")
    let accounts = local.discover().filter { $0.provider == .codex }
    expectEqual(accounts.count, 2)
    expect(accounts[0].isActive)
    expectEqual(try local.credentials(for: accounts[0]).token, "live")
  }
  func testSharedWorkspaceDifferentUsersAreDifferentAccounts() throws {
    let a = try auth("workspace", user: "one")
    let b = try auth("workspace", user: "two")
    expectNotEqual(
      LocalAccounts.codexIdentity(JSON.object(a)), LocalAccounts.codexIdentity(JSON.object(b)))
  }
  func testSwitchPreservesRotatedTokensAndOtherRegistrySettings() throws {
    let live = try auth("one", token: "rotated")
    let target = try auth("two", token: "second")
    try write(live, ".codex/auth.json")
    try write(auth("one", token: "outdated"), ".codex/accounts/one.auth.json")
    try write(auth("one", token: "outdated"), ".codex-swap/accounts/one.auth.json")
    try write(target, ".codex/accounts/two.auth.json")
    try write(JSON.data(["active": "one", "order": ["one"]]), ".codex-swap/state.json")
    try write(
      JSON.data([
        "schema_version": 1, "auto_switch": ["enabled": false],
        "accounts": [
          ["chatgpt_account_id": "two", "email": "two@example.test", "account_key": "key-two"]
        ],
      ]), ".codex/accounts/registry.json")
    let account = try unwrap(local.discover().first { $0.email == "two@example.test" })
    try local.switchAccount(account)
    expectEqual(try Data(contentsOf: root.appendingPathComponent(".codex/auth.json")), target)
    expectEqual(
      try Data(contentsOf: root.appendingPathComponent(".codex/accounts/one.auth.json")), live)
    expectEqual(
      try Data(contentsOf: root.appendingPathComponent(".codex-swap/accounts/one.auth.json")), live)
    let registry = JSON.read(root.appendingPathComponent(".codex/accounts/registry.json"))
    expectEqual(registry["active_account_key"] as? String, "key-two")
    expectEqual((registry["auto_switch"] as? [String: Any])?["enabled"] as? Bool, false)
    expect(JSON.read(root.appendingPathComponent(".codex-swap/state.json"))["active"] is NSNull)
    expectEqual(local.discover().filter { $0.provider == .codex && $0.isActive }.count, 1)
    let attributes = try FileManager.default.attributesOfItem(
      atPath: root.appendingPathComponent(".codex/auth.json").path)
    expectEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }
  func testSwitchRetainsUnsavedCurrentAccount() throws {
    let live = try auth("unsaved")
    try write(live, ".codex/auth.json")
    try write(auth("two"), ".codex/accounts/two.auth.json")
    let target = try unwrap(local.discover().first { $0.email == "two@example.test" })
    try local.switchAccount(target)
    expectEqual(local.discover().filter { $0.provider == .codex }.count, 2)
    let old = try unwrap(local.discover().first { $0.email == "unsaved@example.test" })
    try local.switchAccount(old)
    expectEqual(try Data(contentsOf: root.appendingPathComponent(".codex/auth.json")), live)
  }
  func testTransactionRefusesConcurrentChangeWithoutPartialWrite() throws {
    let a = root.appendingPathComponent("a")
    let b = root.appendingPathComponent("b")
    try PrivateFiles.write(Data("old".utf8), to: a)
    try PrivateFiles.write(Data("concurrent".utf8), to: b)
    expectThrows(
      try FileTransaction.apply([
        FileChange(url: a, before: Data("old".utf8), after: Data("new".utf8)),
        FileChange(url: b, before: Data("old".utf8), after: Data("new".utf8)),
      ]))
    expectEqual(try Data(contentsOf: a), Data("old".utf8))
    expectEqual(try Data(contentsOf: b), Data("concurrent".utf8))
  }
  func testSymlinkRefusedAndTargetUntouched() throws {
    let target = root.appendingPathComponent("target")
    let link = root.appendingPathComponent("link")
    try PrivateFiles.write(Data("safe".utf8), to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    expectThrows(try PrivateFiles.write(Data("unsafe".utf8), to: link))
    expectEqual(try Data(contentsOf: target), Data("safe".utf8))
  }
  func testSubTrackerDataMovesOnceWithoutOverwriting() throws {
    try write(Data("old".utf8), "Library/Application Support/SubTracker/profiles.json")
    expect(LegacyStorage.migrate(local.paths, keychain: false))
    let moved = local.paths.support.appendingPathComponent("profiles.json")
    expectEqual(try Data(contentsOf: moved), Data("old".utf8))
    expect(!LegacyStorage.migrate(local.paths, keychain: false))
    try write(Data("stale".utf8), "Library/Application Support/SubTracker/profiles.json")
    expect(!LegacyStorage.migrate(local.paths, keychain: false))
    expectEqual(try Data(contentsOf: moved), Data("old".utf8))
  }
  func testZaiHostAllowlistRejectsLookalikeAndPlainHTTP() {
    expectEqual(LocalAccounts.zaiHost("https://api.z.ai/api/anthropic"), "api.z.ai")
    expectNil(LocalAccounts.zaiHost("https://api.z.ai.evil.test/api/anthropic"))
    expectNil(LocalAccounts.zaiHost("http://api.z.ai/api/anthropic"))
  }
  func testChangedCodexIdentityCannotBeFetched() throws {
    try write(auth("one"), ".codex/auth.json")
    let original = try unwrap(local.discover().first { $0.provider == .codex })
    try write(auth("two"), ".codex/auth.json")
    expectThrows(try local.credentials(for: original))
  }
  func testNumbersRejectBooleansAndNonFiniteValues() {
    expectNil(JSON.number(true))
    expectNil(JSON.number("nan"))
    expectNil(JSON.number(Double.infinity))
    expectEqual(JSON.number("12.5"), 12.5)
  }
}

// A dependency-free runner also works with Command Line Tools (which do not ship XCTest).
func expect(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
  guard value() else { fatalError("Expectation failed", file: file, line: line) }
}
func expectEqual<T: Equatable>(
  _ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T,
  file: StaticString = #file, line: UInt = #line
) {
  do { guard try lhs() == rhs() else { fatalError("Values differ", file: file, line: line) } } catch
  { fatalError("Unexpected error: \(error)", file: file, line: line) }
}
func expectNotEqual<T: Equatable>(
  _ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line
) { expect(lhs != rhs, file: file, line: line) }
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
  expect(value == nil, file: file, line: line)
}
func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
  expect(value != nil, file: file, line: line)
}
func expectThrows<T>(
  _ work: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line
) {
  do { _ = try work() } catch { return }
  fatalError("Expected an error", file: file, line: line)
}
func unwrap<T>(_ value: T?) throws -> T {
  guard let value else { throw TrackerError.message("Expected a value") }
  return value
}

@main enum Checks {
  static func main() throws {
    if CommandLine.arguments.dropFirst().first == "--agy-fixture" {
      try runAgyFixture()
      return
    }
    let checks: [(String, (NotchSubCoreTests) throws -> Void)] = [
      (
        "testGeminiQuotaRejectsUnknownFractionsAndUsesLowestBucket",
        { try $0.testGeminiQuotaRejectsUnknownFractionsAndUsesLowestBucket() }
      ),
      (
        "testGeminiPlansRespectMigrationAndReportedNames",
        { try $0.testGeminiPlansRespectMigrationAndReportedNames() }
      ),
      (
        "testGeminiDiscoveryIgnoresOldAccountsAndAPIKeys",
        { try $0.testGeminiDiscoveryIgnoresOldAccountsAndAPIKeys() }
      ),
      (
        "testGeminiExpiredAndChangedIdentityNeverRewritesCredentials",
        { try $0.testGeminiExpiredAndChangedIdentityNeverRewritesCredentials() }
      ),
      (
        "testAntigravityGroupedQuotasAndMissingValues",
        { try $0.testAntigravityGroupedQuotasAndMissingValues() }
      ),
      (
        "testAntigravityExecutableAndVersionGates",
        { try $0.testAntigravityExecutableAndVersionGates() }
      ),
      (
        "testAntigravityReportAndDetachedChildCleanup",
        { try $0.testAntigravityReportAndDetachedChildCleanup() }
      ),
      ("testAntigravityTimeoutAndOutputLimit", { try $0.testAntigravityTimeoutAndOutputLimit() }),
      (
        "testZaiCreditWeeklyWindowsAndUnknownTypes",
        { $0.testZaiCreditWeeklyWindowsAndUnknownTypes() }
      ),
      (
        "testChangedZaiKeyCannotBeFetchedUnderOldAccount",
        { try $0.testChangedZaiKeyCannotBeFetchedUnderOldAccount() }
      ),
      (
        "testCodexWeeklyPrimaryAndCreditsAreNotDollars",
        { $0.testCodexWeeklyPrimaryAndCreditsAreNotDollars() }
      ),
      (
        "testClaudeSupportsLegacyAndScopedWindowsWithoutDuplicates",
        { $0.testClaudeSupportsLegacyAndScopedWindowsWithoutDuplicates() }
      ),
      (
        "testMonthlyExtraUsageNeverMasqueradesAsWeeklySpend",
        { $0.testMonthlyExtraUsageNeverMasqueradesAsWeeklySpend() }
      ),
      ("testZaiParsesPercentageAndMCPCounts", { $0.testZaiParsesPercentageAndMCPCounts() }),
      (
        "testExpiredWindowIsStaleAndOverageIsClamped",
        { $0.testExpiredWindowIsStaleAndOverageIsClamped() }
      ),
      (
        "testDiscoveryDeduplicatesProfilesAndUsesLiveCredential",
        { try $0.testDiscoveryDeduplicatesProfilesAndUsesLiveCredential() }
      ),
      (
        "testSharedWorkspaceDifferentUsersAreDifferentAccounts",
        { try $0.testSharedWorkspaceDifferentUsersAreDifferentAccounts() }
      ),
      (
        "testSwitchPreservesRotatedTokensAndOtherRegistrySettings",
        { try $0.testSwitchPreservesRotatedTokensAndOtherRegistrySettings() }
      ),
      (
        "testSwitchRetainsUnsavedCurrentAccount",
        { try $0.testSwitchRetainsUnsavedCurrentAccount() }
      ),
      (
        "testTransactionRefusesConcurrentChangeWithoutPartialWrite",
        { try $0.testTransactionRefusesConcurrentChangeWithoutPartialWrite() }
      ),
      ("testSymlinkRefusedAndTargetUntouched", { try $0.testSymlinkRefusedAndTargetUntouched() }),
      (
        "testSubTrackerDataMovesOnceWithoutOverwriting",
        { try $0.testSubTrackerDataMovesOnceWithoutOverwriting() }
      ),
      (
        "testZaiHostAllowlistRejectsLookalikeAndPlainHTTP",
        { $0.testZaiHostAllowlistRejectsLookalikeAndPlainHTTP() }
      ),
      (
        "testChangedCodexIdentityCannotBeFetched",
        { try $0.testChangedCodexIdentityCannotBeFetched() }
      ),
      (
        "testNumbersRejectBooleansAndNonFiniteValues",
        { $0.testNumbersRejectBooleansAndNonFiniteValues() }
      ),
    ]
    let allChecks =
      checks + NotchSubCoreTests.codingChecks + NotchSubCoreTests.visibilityChecks
      + NotchSubCoreTests.notchChecks
    for (name, run) in allChecks {
      let suite = NotchSubCoreTests()
      try suite.setUpWithError()
      do {
        try run(suite)
        print("PASS \(name)")
      } catch {
        try? suite.tearDownWithError()
        throw error
      }
      try suite.tearDownWithError()
    }
    print("\(allChecks.count) checks passed")
  }
}
