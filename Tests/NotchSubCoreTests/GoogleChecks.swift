import Darwin
import Foundation
import NotchSubCore

extension NotchSubCoreTests {
  func testGeminiQuotaRejectsUnknownFractionsAndUsesLowestBucket() throws {
    let usage = UsageParser.gemini(
      [
        "buckets": [
          ["modelId": "gemini-pro", "remainingFraction": 0.75],
          [
            "modelId": "gemini-pro", "remainingFraction": 0.25, "resetTime": "2026-10-25T12:00:00Z",
          ],
          ["modelId": "gemini-flash", "remainingFraction": 0],
          ["modelId": "missing", "remainingAmount": "100"],
          ["modelId": "boolean", "remainingFraction": true],
          ["modelId": "invalid", "remainingFraction": 1.5],
          ["modelId": "nan", "remainingFraction": Double.nan],
        ]
      ], plan: "Code Assist Standard")
    expectEqual(usage.windows.count, 2)
    expectEqual(usage.windows.first?.remainingPercent, 0)
    expectEqual(usage.windows.last?.remainingPercent, 25)
    expectNotNil(usage.windows.last?.resetsAt)
    expectNil(usage.spend)
    expectEqual(usage.plan, "Code Assist Standard")
  }

  func testGeminiPlansRespectMigrationAndReportedNames() throws {
    expectThrows(
      try UsageParser.geminiPlan([
        "currentTier": ["id": "free-tier"],
        "ineligibleTiers": [["reasonCode": "UNSUPPORTED_CLIENT"]],
      ]))
    expectEqual(
      try UsageParser.geminiPlan([
        "paidTier": ["id": "organization-tier", "name": "Code Assist Enterprise"],
        "currentTier": ["id": "standard-tier"],
      ]), "Code Assist Enterprise")
    expectNil(try UsageParser.geminiPlan(["currentTier": ["id": "unknown-tier"]]))
  }

  func testGeminiDiscoveryIgnoresOldAccountsAndAPIKeys() throws {
    try write(
      JSON.data(["active": "work@example.test", "old": ["old@example.test"]]),
      ".gemini/google_accounts.json")
    expect(local.discoverGoogleAccounts().isEmpty)
    try write(
      JSON.data([
        "access_token": "synthetic-google",
        "expiry_date": Date().addingTimeInterval(300).timeIntervalSince1970 * 1000,
      ]), ".gemini/oauth_creds.json")
    let account = try unwrap(local.discoverGoogleAccounts().first)
    expectEqual(account.email, "work@example.test")
    expectEqual(local.discoverGoogleAccounts().count, 1)
    expect(!account.canSwitch && !account.canCacheUsage)
    expectEqual(try local.credentials(for: account).token, "synthetic-google")
    expectThrows(try local.switchAccount(account))
    try write(
      JSON.data(["security": ["auth": ["selectedType": "gemini-api-key"]]]), ".gemini/settings.json"
    )
    expect(local.discoverGoogleAccounts().isEmpty)
    let isolated = LocalAccounts(
      paths: LocalPaths(
        home: root, environment: ["GEMINI_CLI_HOME": root.appendingPathComponent("alternate").path])
    )
    expect(isolated.discoverGoogleAccounts().isEmpty)
    expectEqual(isolated.paths.gemini.path, root.appendingPathComponent("alternate/.gemini").path)
  }

  func testGeminiExpiredAndChangedIdentityNeverRewritesCredentials() throws {
    let data = try JSON.data(["access_token": "synthetic-google", "expiry_date": 1_700_000_000_000])
    try write(data, ".gemini/oauth_creds.json")
    try write(JSON.data(["active": "first@example.test"]), ".gemini/google_accounts.json")
    let account = try unwrap(local.discoverGoogleAccounts().first)
    expectThrows(try local.credentials(for: account))
    try write(JSON.data(["active": "second@example.test"]), ".gemini/google_accounts.json")
    expectThrows(try local.geminiCredentials(for: account, at: .distantPast))
    expectEqual(try Data(contentsOf: root.appendingPathComponent(".gemini/oauth_creds.json")), data)
    expectEqual(
      LocalAccounts.googleToken(["token": ["accessToken": "keychain-synthetic"]]),
      "keychain-synthetic")
    expectNil(LocalAccounts.googleToken(["token": ["accessToken": ""]]))
  }

  func testAntigravityGroupedQuotasAndMissingValues() throws {
    let usage = try UsageParser.antigravity(googleUsageFixture)
    expectEqual(usage.windows.map(\.remainingPercent), [50, 0])
    expectEqual(usage.windows.first?.title, "Gemini Models · Weekly")
    expectNotNil(usage.windows.first?.resetsAt)
    expectNil(usage.plan)
    expectNil(usage.spend)
    expectThrows(
      try UsageParser.antigravity(["status": "ERROR", "command": ["name": "usage", "data": [:]]]))
    expectThrows(
      try UsageParser.antigravity([
        "status": "SUCCESS", "command": ["name": "prompt", "data": [:]],
      ]))
    expectThrows(
      try UsageParser.antigravity([
        "status": "SUCCESS", "command": ["name": "usage", "data": ["groups": []]],
      ]))
  }

  func testAntigravityExecutableAndVersionGates() throws {
    let executable = try agyFixture("old")
    let paths = LocalPaths(home: root, environment: ["ANTIGRAVITY_CLI_PATH": executable.path])
    let accounts = LocalAccounts(paths: paths).discoverGoogleAccounts()
    expectEqual(accounts.count, 1)
    expect(!accounts[0].isActive && !accounts[0].canSwitch && !accounts[0].canCacheUsage)
    expectThrows(try AntigravityUsage.fetch(executable: executable, timeout: 2))
    expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("usage-ran").path))
    expectNil(
      AntigravityUsage.executable(
        home: root, environment: ["ANTIGRAVITY_CLI_PATH": "", "PATH": root.path]))
    expect(!AntigravityUsage.supportsUsageReport("unknown"))
    expect(!AntigravityUsage.supportsUsageReport("1.1.10"))
    expect(AntigravityUsage.supportsUsageReport("Antigravity CLI 1.1.11"))
    expect(AntigravityUsage.supportsUsageReport("1.2.0"))
  }

  func testAntigravityReportAndDetachedChildCleanup() throws {
    let executable = try agyFixture("success")
    let snapshot = try AntigravityUsage.fetch(executable: executable, timeout: 3)
    expectEqual(snapshot.windows.count, 2)
    try expectFixtureChildStopped()
  }

  func testAntigravityTimeoutAndOutputLimit() throws {
    var executable = try agyFixture("timeout")
    let start = ProcessInfo.processInfo.systemUptime
    expectThrows(try AntigravityUsage.fetch(executable: executable, timeout: 0.5))
    expect(ProcessInfo.processInfo.systemUptime - start < 5)
    try expectFixtureChildStopped()
    executable = try agyFixture("large")
    expectThrows(try AntigravityUsage.fetch(executable: executable, timeout: 2))
  }

  private func agyFixture(_ mode: String) throws -> URL {
    func quote(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    let executable = root.appendingPathComponent("agy")
    let checker = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    let script =
      "#!/bin/sh\nexec \(quote(checker)) --agy-fixture \(mode) \(quote(root.path)) \"$@\"\n"
    try PrivateFiles.write(Data(script.utf8), to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return executable
  }

  private func expectFixtureChildStopped() throws {
    let text = try String(contentsOf: root.appendingPathComponent("child-pid"), encoding: .utf8)
    let pid = try unwrap(Int32(text))
    for _ in 0..<50 {
      var info = proc_bsdinfo()
      let found = proc_pidinfo(
        pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
      if found <= 0 || info.pbi_status == SZOMB { return }
      usleep(20_000)
    }
    // Clean up the fixture even if a future regression breaks production cleanup.
    kill(pid, SIGKILL)
    expect(false)
  }
}

let googleUsageFixture: [String: Any] = [
  "status": "SUCCESS",
  "command": [
    "name": "usage",
    "data": [
      "groups": [
        [
          "display_name": "Gemini Models",
          "buckets": [
            [
              "bucket_id": "weekly", "display_name": "Weekly", "remaining_fraction": 0.5,
              "reset_time": "2026-10-25T12:00:00Z",
            ],
            ["bucket_id": "missing", "remaining_amount": "100"],
            ["bucket_id": "disabled", "disabled": true, "remaining_fraction": 1],
          ],
        ],
        [
          "displayName": "Claude and GPT models",
          "buckets": [
            [
              "bucketId": "weekly", "displayName": "Weekly",
              "remaining": ["case": "remainingFraction", "value": 0],
            ]
          ],
        ],
      ]
    ],
  ],
]

func runAgyFixture() throws {
  let args = CommandLine.arguments
  let mode = args[2]
  let root = URL(fileURLWithPath: args[3])
  if mode == "detached" {
    _ = setsid()
    _ = setpgid(0, 0)
    try String(getpid()).write(
      to: root.appendingPathComponent("child-pid"), atomically: true, encoding: .utf8)
    sleep(10)
    return
  }
  if args.last == "--version" {
    print(mode == "old" ? "1.1.10" : "1.2.11")
    return
  }
  guard Array(args.dropFirst(4)) == ["-p", "/usage", "--output-format", "json"],
    ProcessInfo.processInfo.environment["AGY_CLI_DISABLE_AUTO_UPDATE"] == "true",
    let browser = ProcessInfo.processInfo.environment["BROWSER"]
  else { exit(3) }
  let launcher = Process()
  launcher.executableURL = URL(fileURLWithPath: browser)
  try launcher.run()
  launcher.waitUntilExit()
  guard launcher.terminationStatus != 0 else { exit(4) }
  try Data().write(to: root.appendingPathComponent("usage-ran"))
  if mode == "large" {
    print(String(repeating: "x", count: 1_100_000))
    return
  }
  let child = Process()
  child.executableURL = URL(fileURLWithPath: args[0])
  child.arguments = ["--agy-fixture", "detached", root.path]
  child.standardOutput = FileHandle.nullDevice
  child.standardError = FileHandle.nullDevice
  try child.run()
  usleep(100_000)
  if mode == "timeout" { sleep(10) }
  print(String(decoding: try JSON.data(googleUsageFixture), as: UTF8.self))
}
