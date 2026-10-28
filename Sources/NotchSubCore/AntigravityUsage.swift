import Darwin
import Foundation

public enum AntigravityUsage {
  public static func executable(home: URL, environment: [String: String]) -> URL? {
    let fm = FileManager.default
    if let override = environment["ANTIGRAVITY_CLI_PATH"] {
      guard override.hasPrefix("/"), fm.isExecutableFile(atPath: override) else { return nil }
      return URL(fileURLWithPath: override)
    }
    var candidates = (environment["PATH"] ?? "").split(separator: ":")
      .filter { $0.hasPrefix("/") }.map {
        URL(fileURLWithPath: String($0)).appendingPathComponent("agy")
      }
    candidates += [
      home.appendingPathComponent(".local/bin/agy"), home.appendingPathComponent("bin/agy"),
    ]
    if home == fm.homeDirectoryForCurrentUser {
      candidates += [
        URL(fileURLWithPath: "/opt/homebrew/bin/agy"), URL(fileURLWithPath: "/usr/local/bin/agy"),
      ]
    }
    return candidates.first { fm.isExecutableFile(atPath: $0.path) }
  }

  public static func supportsUsageReport(_ version: String) -> Bool {
    guard let range = version.range(of: #"\b\d+\.\d+\.\d+\b"#, options: .regularExpression) else {
      return false
    }
    let numbers = version[range].split(separator: ".").compactMap { Int($0) }
    guard numbers.count == 3 else { return false }
    return !numbers.lexicographicallyPrecedes([1, 1, 11])
  }

  public static func fetch(executable: URL, timeout: TimeInterval = 45) throws -> UsageSnapshot {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "notchsub-agy-\(UUID().uuidString)")
    try PrivateFiles.directory(directory)
    defer { try? FileManager.default.removeItem(at: directory) }
    // A usage refresh must not open a browser login or update the user's CLI.
    for launcher in ["open", "xdg-open", "browser"] {
      let file = directory.appendingPathComponent(launcher)
      try PrivateFiles.write(Data("#!/bin/sh\nexit 1\n".utf8), to: file)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    }
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = directory.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
    environment["BROWSER"] = directory.appendingPathComponent("browser").path
    environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
    // Some configured MCP servers detach from the process group. Track only this probe's descendants.
    let owner = "NOTCHSUB_AGY_PROBE=" + UUID().uuidString
    environment["NOTCHSUB_AGY_PROBE"] = String(owner.dropFirst("NOTCHSUB_AGY_PROBE=".count))
    defer { stopOwnedProcesses(marker: owner) }
    let version = try run(
      executable, arguments: ["--version"], directory: directory,
      environment: environment, timeout: min(5, timeout), maximumBytes: 16384)
    guard supportsUsageReport(String(decoding: version, as: UTF8.self)) else {
      throw TrackerError.message("Update Antigravity CLI to 1.1.11 or later")
    }
    let report = try run(
      executable, arguments: ["-p", "/usage", "--output-format", "json"],
      directory: directory, environment: environment, timeout: timeout)
    return try UsageParser.antigravity(JSON.object(report))
  }

  private static func stopOwnedProcesses(marker: String) {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return }
    var pids = [pid_t](repeating: 0, count: Int(count) + 128)
    let bytes = Int32(pids.count * MemoryLayout<pid_t>.stride)
    let found = proc_listallpids(&pids, bytes)
    guard found > 0 else { return }
    let markerBytes = Array(marker.utf8)
    for pid in pids.prefix(min(Int(found), pids.count)) where pid > 1 && pid != getpid() {
      var info = proc_bsdinfo()
      let size = Int32(MemoryLayout<proc_bsdinfo>.size)
      guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
        info.pbi_uid == getuid()
      else { continue }
      // KERN_PROCARGS2 includes argv and the environment. Match an entire NUL-delimited field.
      var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
      var length = 0
      guard sysctl(&mib, 3, nil, &length, nil, 0) == 0, length > 0, length <= 1_048_576 else {
        continue
      }
      var buffer = [UInt8](repeating: 0, count: length)
      guard sysctl(&mib, 3, &buffer, &length, nil, 0) == 0,
        buffer.prefix(length).split(separator: 0).contains(where: { $0.elementsEqual(markerBytes) })
      else { continue }
      var current = proc_bsdinfo()
      guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &current, size) == size,
        current.pbi_uid == info.pbi_uid, current.pbi_start_tvsec == info.pbi_start_tvsec,
        current.pbi_start_tvusec == info.pbi_start_tvusec
      else { continue }
      kill(pid, SIGKILL)
    }
  }

  // Spawn a dedicated process group, drain bounded output, and stop only that group on every exit.
  // No shell evaluates the command, stdout/stderr are never logged, and stdin is closed.
  static func run(
    _ executable: URL, arguments: [String], directory: URL,
    environment: [String: String], timeout: TimeInterval,
    maximumBytes: Int = 1_048_576
  ) throws -> Data {
    var descriptors: [Int32] = [0, 0]
    guard pipe(&descriptors) == 0 else {
      throw TrackerError.message("Could not read Antigravity usage")
    }
    defer { close(descriptors[0]) }
    let null = open("/dev/null", O_RDWR)
    guard null >= 0 else {
      close(descriptors[1])
      throw TrackerError.message("Could not start Antigravity")
    }
    defer { close(null) }
    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attributes)
    defer {
      posix_spawn_file_actions_destroy(&actions)
      posix_spawnattr_destroy(&attributes)
    }
    posix_spawn_file_actions_adddup2(&actions, null, STDIN_FILENO)
    posix_spawn_file_actions_adddup2(&actions, null, STDERR_FILENO)
    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
    posix_spawn_file_actions_addclose(&actions, descriptors[0])
    posix_spawn_file_actions_addclose(&actions, descriptors[1])
    posix_spawn_file_actions_addchdir_np(&actions, directory.path)
    posix_spawnattr_setflags(
      &attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
    posix_spawnattr_setpgroup(&attributes, 0)
    let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
    let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { for p in argv + envp { free(p) } }
    var pid: pid_t = 0
    let result = argv.withUnsafeBufferPointer { a in
      envp.withUnsafeBufferPointer { e in
        posix_spawn(
          &pid, executable.path, &actions, &attributes,
          UnsafeMutablePointer(mutating: a.baseAddress!),
          UnsafeMutablePointer(mutating: e.baseAddress!))
      }
    }
    close(descriptors[1])
    guard result == 0 else { throw TrackerError.message("Could not start Antigravity CLI") }
    var reaped = false
    defer {
      kill(-pid, SIGKILL)
      if !reaped {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
      }
    }
    _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
    var output = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    let deadline = ProcessInfo.processInfo.systemUptime + max(0.1, timeout)
    while true {
      try Task.checkCancellation()
      while true {
        let count = read(descriptors[0], &buffer, buffer.count)
        if count <= 0 { break }
        guard output.count + count <= maximumBytes else {
          throw TrackerError.message("Antigravity report too large")
        }
        output.append(contentsOf: buffer.prefix(count))
      }
      var status: Int32 = 0
      let wait = waitpid(pid, &status, WNOHANG)
      if wait == pid {
        reaped = true
        guard status == 0 else {
          throw TrackerError.message("Open Antigravity CLI to check sign-in")
        }
        // Read any bytes written between the last drain and process exit.
        while true {
          let count = read(descriptors[0], &buffer, buffer.count)
          if count <= 0 { break }
          guard output.count + count <= maximumBytes else {
            throw TrackerError.message("Antigravity report too large")
          }
          output.append(contentsOf: buffer.prefix(count))
        }
        return output
      }
      guard wait >= 0 || errno == EINTR else {
        throw TrackerError.message("Antigravity usage unavailable")
      }
      guard ProcessInfo.processInfo.systemUptime < deadline else {
        throw TrackerError.message("Antigravity usage timed out")
      }
      usleep(20_000)
    }
  }
}
