import Foundation

/// Notch Sub shipped as Sub Tracker through 0.4.3. Its saved data moves over once, at launch.
public enum LegacyStorage {
  public static let defaultsDomain = "com.sagar.subtracker"
  static let folder = "Library/Application Support/SubTracker"
  static let service = "com.sagar.subtracker.accounts"

  /// Moves Sub Tracker's support folder and Keychain items unless Notch Sub already has data.
  /// Returns whether the folder moved. Old Keychain items stay, since deleting them can prompt.
  @discardableResult
  public static func migrate(_ paths: LocalPaths, keychain: Bool = true) -> Bool {
    let fm = FileManager.default
    let old = paths.home.appendingPathComponent(folder)
    guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: paths.support.path) else {
      return false
    }
    // Keychain first: if the move fails, the next launch retries both.
    if keychain {
      for account in KeychainStore.accounts(service: service) {
        guard let data = try? KeychainStore.read(service: service, account: account) else {
          continue
        }
        try? KeychainStore.write(data, account: account)
      }
    }
    do {
      try fm.createDirectory(
        at: paths.support.deletingLastPathComponent(), withIntermediateDirectories: true)
      try fm.moveItem(at: old, to: paths.support)
      return true
    } catch {
      return false
    }
  }
}
