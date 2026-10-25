import Foundation
import SQLite3
import SubTrackerCore

extension SubTrackerCoreTests {
  static var codingChecks: [(String, (SubTrackerCoreTests) throws -> Void)] {
    [
      ("Copilot request quotas and unlimited pools", { try $0.testCopilotQuotas() }),
      ("Copilot credits do not invent a denominator", { try $0.testCopilotCredits() }),
      ("Cursor percentage units and shared weekly pool", { try $0.testCursorQuotas() }),
      ("Kimi current and legacy windows", { try $0.testKimiQuotas() }),
      ("MiniMax remaining counts and shared percentages", { try $0.testMiniMaxQuotas() }),
      ("MiniMax multi-service and rejected credentials", { try $0.testMiniMaxServices() }),
      ("OpenCode API percentages and reset timestamps", { try $0.testOpenCodeQuotas() }),
      ("Kiro overage, trial, and ambiguous bonus pools", { try $0.testKiroQuotas() }),
      ("Devin cache is never presented as live", { try $0.testDevinCache() }),
      ("Missing provider quotas remain unknown", { try $0.testMissingCodingQuotas() }),
      ("SQLite reads preserve files and bind keys", { try $0.testReadOnlyDatabase() }),
      ("SQLite reads include committed WAL values", { try $0.testReadOnlyWAL() }),
      ("Regional keys and changed identities", { try $0.testRegionalCodingKeys() }),
      ("Kimi OAuth scopes and expiration", { try $0.testKimiOAuthScopes() }),
      ("Copilot ignores unrelated and enterprise tokens", { try $0.testCopilotDiscovery() }),
      ("Cursor editor takes precedence over CLI", { try $0.testCursorDiscovery() }),
      ("Kiro region selection and read-only switching", { try $0.testKiroDiscovery() }),
      ("Saved key visibility and older usage cache", { try $0.testCodingCompatibility() }),
    ]
  }

  func testCopilotQuotas() throws {
    let s = try UsageParser.copilot([
      "copilot_plan": "pro", "quota_reset_date": "2026-11-01",
      "quota_snapshots": [
        "premium_interactions": ["entitlement": 300, "percent_remaining": 0],
        "completions": ["unlimited": true, "entitlement": -1],
      ],
    ])
    expectEqual(s.windows.first?.remainingPercent, 0)
    expectNotNil(s.windows.first?.resetsAt)
    expectEqual(s.metrics?.first?.value, "Unlimited")
    expectNil(s.spend)
  }
  func testCopilotCredits() throws {
    let s = try UsageParser.copilot([
      "token_based_billing": true,
      "quota_snapshots": [
        "premium_interactions": [
          "credits_used": 12.5, "entitlement": 300, "percent_remaining": 100,
        ],
        "chat": ["credits_used": 12.5, "unlimited": true],
      ],
    ])
    expect(s.windows.isEmpty)
    expectEqual(s.metrics?.count, 2)
    expectEqual(s.metrics?.last?.value, "Not reported")
    expectNil(s.spend)
  }
  func testCursorQuotas() throws {
    let raw: [String: Any] = [
      "individualUsage": ["plan": ["autoPercentUsed": 0.36, "apiPercentUsed": 49]]
    ]
    let monthly = try UsageParser.cursor(raw)
    expectEqual(monthly.windows.map(\.usedPercent), [0.36, 49])
    var unavailable = raw
    unavailable["membershipType"] = "unified_pro"
    unavailable["limitType"] = "user"
    expectThrows(try UsageParser.cursor(unavailable))
    let unified = try UsageParser.cursor(
      raw,
      shared: [
        "isUnified": true, "hasNonZeroIncludedLimit": true, "usagePercent": 12,
        "nextResetTimestampUtc": "2026-11-01T12:00:00Z",
      ])
    expectEqual(unified.windows.map(\.title), ["Weekly"])
    expectEqual(unified.windows.first?.remainingPercent, 88)
    expectThrows(
      try UsageParser.cursor(raw, shared: ["isUnified": true, "includedLimitZero": true]))
  }
  func testKimiQuotas() throws {
    let s = try UsageParser.kimi([
      "usages": [
        "limit_5h": ["used_ratio": 0.25, "reset_time": "2026-11-01T12:00:00Z"],
        "limit_month_code": ["used_ratio": 1.1],
      ], "boosterWallet": ["monthlyUsedCents": 500],
    ])
    expectEqual(s.windows.map(\.title), ["5 hours", "Coding · monthly"])
    expectEqual(s.windows.map(\.remainingPercent), [75, 0])
    expectNil(s.spend)
    let legacy = try UsageParser.kimi([
      "usage": ["limit": 100, "remaining": 70],
      "limits": [
        [
          "window": ["duration": 300, "timeUnit": "TIME_UNIT_MINUTE"],
          "detail": ["limit": 40, "used": 10],
        ]
      ],
    ])
    expectEqual(legacy.windows.map(\.title), ["Weekly", "5 hours"])
    expectEqual(legacy.windows.map(\.remainingPercent), [70, 75])
  }
  func testMiniMaxQuotas() throws {
    let counts = try UsageParser.minimax([
      "model_remains": [
        [
          "model_name": "MiniMax-M2.7",
          "current_interval_total_count": 100, "current_interval_usage_count": 30,
          "current_interval_remaining_percent": 0,
        ]
      ]
    ])
    expectEqual(counts.windows.first?.remainingPercent, 30)
    let shared = try UsageParser.minimax([
      "data": [
        "model_remains": [
          [
            "model_name": "general",
            "current_interval_total_count": 0, "current_interval_usage_count": 0,
            "current_interval_remaining_percent": 64,
            "current_weekly_remaining_percent": 0,
          ], ["model_name": "MiniMax-M3", "current_interval_remaining_percent": 64],
        ]
      ]
    ])
    expectEqual(shared.windows.map(\.remainingPercent), [64, 0])
    expectNil(shared.spend)
  }
  func testMiniMaxServices() throws {
    let s = try UsageParser.minimax([
      "data": [
        "services": [
          [
            "service_type": "Text", "window_type": "Weekly", "usage": 40, "limit": 100,
            "time_range": "unknown",
          ]
        ]
      ]
    ])
    expectEqual(s.windows.first?.remainingPercent, 60)
    expectNil(s.windows.first?.resetsAt)
    expectThrows(
      try UsageParser.minimax(["base_resp": ["status_code": 1004], "points_balance": 100]))
  }
  func testOpenCodeQuotas() throws {
    let s = try UsageParser.opencode([
      "usage": [
        "rolling": ["status": "ok", "percent": 0.5, "resetsAt": "2026-11-01T12:00:00Z"],
        "weekly": ["percent": 100], "monthly": ["percent": 41],
      ]
    ])
    expectEqual(s.windows.map(\.remainingPercent), [99.5, 0, 59])
    expectNotNil(s.windows.first?.resetsAt)
    expectNil(s.spend)
  }
  func testKiroQuotas() throws {
    var credit: [String: Any] = [
      "resourceType": "CREDIT", "currentUsageWithPrecision": 120,
      "usageLimitWithPrecision": 100, "currentOveragesWithPrecision": 20,
      "overageCapWithPrecision": 50,
    ]
    let s = try UsageParser.kiro([
      "usageBreakdownList": [credit], "overageConfiguration": ["overageStatus": "ENABLED"],
    ])
    expectEqual(s.windows.map(\.remainingPercent), [0, 60])
    credit["bonuses"] = [["usageLimit": 100]]
    credit["freeTrialInfo"] = ["freeTrialStatus": "ACTIVE", "currentUsage": 5, "usageLimit": 20]
    let b = try UsageParser.kiro(["usageBreakdownList": [credit]])
    expectEqual(b.windows.map(\.title), ["Trial credits"])
    expectEqual(b.metrics?.last?.value, "Not reported")
    expectNil(b.spend)
  }
  func testDevinCache() throws {
    let s = try UsageParser.windsurf(
      ["quotaUsage": ["dailyRemainingPercent": 90, "weeklyRemainingPercent": 40]], at: Date())
    expectEqual(s.windows.map(\.remainingPercent), [90, 40])
    expect(s.isStale())
    expectEqual(s.source, "Local cache")
  }
  func testMissingCodingQuotas() throws {
    for parse in [
      UsageParser.copilot, UsageParser.cursorWithoutShared, UsageParser.kimi, UsageParser.minimax,
      UsageParser.opencode, UsageParser.kiro,
    ] {
      expectThrows(try parse([:], Date()))
    }
    expectThrows(try UsageParser.kimi(["usages": ["limit_5h": ["used_ratio": true]]]))
    expectThrows(
      try UsageParser.opencode(["usage": ["rolling": ["used": 1e308, "limit": 1e-308]]]))
  }

  func database(
    _ relative: String, table: String = "ItemTable", values: [String: Data], wal: Bool = false
  ) throws -> (URL, OpaquePointer?) {
    let url = root.appendingPathComponent(relative)
    try PrivateFiles.directory(url.deletingLastPathComponent())
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
      throw TrackerError.message("Fixture database failed")
    }
    if wal { sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) }
    sqlite3_exec(
      db, "CREATE TABLE IF NOT EXISTS \(table) (key TEXT PRIMARY KEY, value BLOB);", nil, nil, nil)
    for (key, data) in values {
      var stmt: OpaquePointer?
      sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO \(table) VALUES (?, ?)", -1, &stmt, nil)
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(stmt, 1, key, -1, transient)
      _ = data.withUnsafeBytes {
        sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), transient)
      }
      expectEqual(sqlite3_step(stmt), SQLITE_DONE)
      sqlite3_finalize(stmt)
    }
    if !wal {
      sqlite3_close(db)
      db = nil
    }
    return (url, db)
  }
  func testReadOnlyDatabase() throws {
    let (url, _) = try database(
      "app/state.vscdb",
      values: [
        "safe": Data("value".utf8),
        "utf16": "jwt.payload.signature".data(using: .utf16LittleEndian)!,
      ])
    let before = try Data(contentsOf: url)
    let files = try FileManager.default.contentsOfDirectory(
      atPath: url.deletingLastPathComponent().path
    ).sorted()
    expectEqual(LocalDatabase.text(LocalDatabase.value(at: url, key: "safe")), "value")
    expectEqual(
      LocalDatabase.text(LocalDatabase.value(at: url, key: "utf16")), "jwt.payload.signature")
    expectNil(LocalDatabase.value(at: url, key: "' OR 1=1 --"))
    expectNil(LocalDatabase.value(at: url, table: "secrets", key: "safe"))
    expectEqual(try Data(contentsOf: url), before)
    expectEqual(
      try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        .sorted(), files)
    let missing = root.appendingPathComponent("absent.db")
    expectNil(LocalDatabase.value(at: missing, key: "safe"))
    expect(!FileManager.default.fileExists(atPath: missing.path))
  }
  func testReadOnlyWAL() throws {
    let (url, db) = try database(
      "wal/state.vscdb", values: ["safe": Data("newest".utf8)], wal: true)
    defer { sqlite3_close(db) }
    expectEqual(LocalDatabase.text(LocalDatabase.value(at: url, key: "safe")), "newest")
    let copy = root.appendingPathComponent("incomplete.db")
    try FileManager.default.copyItem(at: url, to: copy)
    try FileManager.default.copyItem(atPath: url.path + "-wal", toPath: copy.path + "-wal")
    expectNil(LocalDatabase.value(at: copy, key: "safe"))
    expect(!FileManager.default.fileExists(atPath: copy.path + "-shm"))
  }
  func testRegionalCodingKeys() throws {
    try write(
      JSON.data([
        "env": [
          "ANTHROPIC_BASE_URL": "https://api.minimax.cn/anthropic/v1",
          "ANTHROPIC_AUTH_TOKEN": "sk-cp-fixture-cn",
        ]
      ]), ".claude/settings.json")
    let cn = try unwrap(local.discoverAdditionalAccounts().first { $0.provider == .minimax })
    expectEqual(try local.credentials(for: cn).host, "www.minimax.cn")
    try write(JSON.data([:]), ".claude/settings.json")

    try write(
      JSON.data([
        "kimi-code-plan-cn": ["type": "api", "key": "synthetic-same"],
        "kimi-code-plan-global": ["type": "api", "key": "synthetic-same"],
        "minimax-coding-plan": ["type": "api", "key": "sk-api-standard"],
        "opencode-go": ["type": "api", "key": "synthetic-go"],
      ]), ".local/share/opencode/auth.json")
    let accounts = local.discoverAdditionalAccounts()
    expectEqual(accounts.filter { $0.provider == .kimi }.count, 2)
    expectEqual(Set(accounts.map(\.id)).count, accounts.count)
    expect(!accounts.contains { $0.provider == .minimax })
    let first = try unwrap(accounts.first { $0.provider == .opencode })
    try write(
      JSON.data(["opencode-go": ["type": "api", "key": "changed"]]),
      ".local/share/opencode/auth.json")
    expectThrows(try local.credentials(for: first))
    let foreign = LocalAccounts(
      paths: LocalPaths(
        home: root,
        environment: [
          "KIMI_CODE_API_KEY": "synthetic", "KIMI_CODE_BASE_URL": "https://api.kimi.ai.evil.test",
        ]))
    expect(!foreign.discoverAdditionalAccounts().contains { $0.provider == .kimi })
  }
  func testKimiOAuthScopes() throws {
    let scope =
      "{\"oauthHost\":\"https://auth.kimi.ai\",\"baseUrl\":\"https://api.kimi.ai/coding/v1\"}"
    let name = "kimi-code-env-" + PrivateFiles.digest(Data(scope.utf8)).prefix(16)
    try write(
      JSON.data([
        "access_token": "synthetic-cn",
        "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970,
      ]), ".kimi-code/credentials/kimi-code.json")
    try write(
      JSON.data(["access_token": "synthetic-global", "expires_at": 1]),
      ".kimi-code/credentials/\(name).json")
    let accounts = local.discoverAdditionalAccounts().filter { $0.provider == .kimi }
    expectEqual(accounts.count, 2)
    let expired = try unwrap(accounts.first { $0.issue != nil })
    expectThrows(try local.credentials(for: expired))
    let current = try unwrap(accounts.first { $0.issue == nil })
    expectEqual(try local.credentials(for: current).host, "api.kimi.com")
  }
  func testCopilotDiscovery() throws {
    let env = LocalAccounts(
      paths: LocalPaths(
        home: root, environment: ["GH_TOKEN": "synthetic", "GITHUB_TOKEN": "synthetic"]))
    expect(!env.discoverAdditionalAccounts().contains { $0.provider == .copilot })
    try write(
      JSON.data([
        "github.enterprise.test": ["oauth_token": "synthetic-private"],
        "github.com": ["oauth_token": "synthetic-public", "user": "fixture-user"],
      ]), ".config/github-copilot/hosts.json")
    let accounts = local.discoverAdditionalAccounts().filter { $0.provider == .copilot }
    expectEqual(accounts.count, 1)
    expectEqual(try local.credentials(for: accounts[0]).accountID, "fixture-user")
  }
  func cursorToken(_ user: String) throws -> String {
    let claims = try JSON.data([
      "sub": "auth0|\(user)", "exp": Date().addingTimeInterval(3600).timeIntervalSince1970,
    ]).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(
      of: "+", with: "-"
    ).replacingOccurrences(of: "/", with: "_")
    return "header.\(claims).signature"
  }
  func testCursorDiscovery() throws {
    let token = try cursorToken("editor")
    _ = try database(
      "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
      values: ["cursorAuth/accessToken": Data(token.utf8)])
    try write(JSON.data(["accessToken": try cursorToken("cli")]), ".config/cursor/auth.json")
    let accounts = local.discoverAdditionalAccounts().filter { $0.provider == .cursor }
    expectEqual(accounts.count, 1)
    expectEqual(try local.credentials(for: accounts[0]).token, token)
    expect(!accounts[0].canSwitch)
  }
  func testKiroDiscovery() throws {
    let arn = "arn:aws:codewhisperer:eu-central-1:123:profile/fixture"
    expectEqual(LocalAccounts.kiroHost(profileARN: arn), "q.eu-central-1.amazonaws.com")
    expectNil(LocalAccounts.kiroHost(profileARN: "arn:aws:codewhisperer:unknown:123:profile/test"))
    let path = "Library/Application Support/kiro-cli/data.sqlite3"
    _ = try database(
      path, table: "auth_kv",
      values: [
        "kirocli:odic:token": try JSON.data([
          "access_token": "synthetic",
          "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970,
        ])
      ])
    _ = try database(
      path, table: "state", values: ["api.codewhisperer.profile": try JSON.data(["arn": arn])])
    let a = try unwrap(local.discoverAdditionalAccounts().first { $0.provider == .kiro })
    expectEqual(try local.credentials(for: a).host, "q.eu-central-1.amazonaws.com")
    expectThrows(try local.switchAccount(a))
  }
  func testCodingCompatibility() throws {
    let account = Account(
      id: "key", provider: .kimi, name: "", source: .vault("key"), canSwitch: false)
    expect(account.showsInCompactView)
    expect(!account.isActive)
    let data = try JSONEncoder().encode(UsageSnapshot())
    var object = JSON.object(data)
    object.removeValue(forKey: "metrics")
    let restored = try JSONDecoder().decode(UsageSnapshot.self, from: JSON.data(object))
    expectNil(restored.metrics)
  }
}

extension UsageParser {
  fileprivate static func cursorWithoutShared(_ json: [String: Any], at date: Date) throws
    -> UsageSnapshot
  {
    try cursor(json, at: date)
  }
}
