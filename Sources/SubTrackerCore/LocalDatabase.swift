import Foundation
import SQLite3

/// Reads only the named application value. It never creates a database or missing WAL sidecars.
public enum LocalDatabase {
  public static func value(at file: URL, table: String = "ItemTable", key: String) -> Data? {
    guard ["ItemTable", "auth_kv", "state"].contains(table),
      FileManager.default.isReadableFile(atPath: file.path)
    else { return nil }
    var parts = URLComponents(url: file, resolvingAgainstBaseURL: false)
    let hasWAL = FileManager.default.fileExists(atPath: file.path + "-wal")
    let hasSHM = FileManager.default.fileExists(atPath: file.path + "-shm")
    // Do not ignore an active WAL; require its existing shared-memory sidecar.
    guard !hasWAL || hasSHM else { return nil }
    parts?.queryItems =
      [URLQueryItem(name: "mode", value: "ro")]
      + (hasWAL ? [] : [URLQueryItem(name: "immutable", value: "1")])
    guard let path = parts?.string else { return nil }
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK
    else {
      sqlite3_close(db)
      return nil
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 250)
    sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 1_048_576)
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        db, "SELECT value FROM \(table) WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK
    else { return nil }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    guard sqlite3_bind_text(statement, 1, key, -1, transient) == SQLITE_OK,
      sqlite3_step(statement) == SQLITE_ROW
    else { return nil }
    let count = Int(sqlite3_column_bytes(statement, 0))
    guard count > 0, count <= 1_048_576, let bytes = sqlite3_column_blob(statement, 0) else {
      return nil
    }
    return Data(bytes: bytes, count: count)
  }

  public static func text(_ data: Data?) -> String? {
    guard let data, !data.isEmpty else { return nil }
    let bytes = Array(data)
    // Cursor sometimes stores ASCII tokens as UTF-16LE without a BOM.
    if bytes.count.isMultiple(of: 2),
      stride(from: 1, to: bytes.count, by: 2).allSatisfy({ bytes[$0] == 0 })
    {
      return String(data: data, encoding: .utf16LittleEndian)
    }
    return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
  }
}
