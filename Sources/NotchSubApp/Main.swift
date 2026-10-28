import AppKit
import NotchSubCore
import ServiceManagement
import SwiftUI

@main enum Main {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var item: NSStatusItem?
  private let popover = NSPopover()
  private var settingsWindow: NSWindow?
  private var previewWindow: NSWindow?
  private var timer: Timer?
  private var store: TrackerStore!
  private var wakeObserver: NSObjectProtocol?
  private var notch: NotchController?
  private var displayObserver: NSObjectProtocol?
  private var hasHardwareNotch: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let args = CommandLine.arguments
    if !args.contains("--demo") { migrateFromSubTracker() }
    if let index = args.firstIndex(of: "--placement"), args.indices.contains(index + 1),
      let placement = Placement(rawValue: args[index + 1])
    {
      UserDefaults.standard.set(placement.rawValue, forKey: "placement")
    }
    store = TrackerStore(
      demo: args.contains("--demo"), googleDemo: args.contains("--google"),
      codingDemo: args.contains("--coding"))
    if args.contains("--diagnose") {
      Task {
        await store.refresh()
        // Deliberately excludes names, emails, paths, IDs, and all credentials.
        let rows: [[String: Any]] = store.accounts.map { a in
          [
            "provider": a.provider.rawValue, "active": a.isActive, "plan": a.planLabel ?? "unknown",
            "visible": a.canDisplayUsage,
            "windows": a.usage?.windows.map {
              ["label": $0.title, "remaining": $0.remainingPercent] as [String: Any]
            } ?? [],
            "source": a.usage?.source ?? "none", "issue": a.issue ?? "none",
          ]
        }
        if let data = try? JSONSerialization.data(
          withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8)
        {
          print(text)
        }
        NSApplication.shared.terminate(nil)
      }
      return
    }
    if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
      Task {
        if !args.contains("--demo") { await store.refresh() }
        if args.contains("--dark") {
          NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        if args.contains("--light") { NSApplication.shared.appearance = NSAppearance(named: .aqua) }
        let isSettings = args.contains("--settings")
        let content =
          isSettings
          ? AnyView(SettingsView(store: store))
          : AnyView(TrackerView(store: store, showSettings: {}))
        let view = NSHostingView(rootView: content)
        let size = view.fittingSize
        view.frame = NSRect(
          origin: .zero,
          size: NSSize(
            width: isSettings ? 410 : 382,
            height: isSettings ? size.height : max(400, min(700, size.height))))
        let window = NSWindow(
          contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.display()
        view.layoutSubtreeIfNeeded()
        do {
          guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw TrackerError.message("Could not render snapshot")
          }
          view.cacheDisplay(in: view.bounds, to: rep)
          guard let png = rep.representation(using: .png, properties: [:]) else {
            throw TrackerError.message("Could not encode snapshot")
          }
          try png.write(to: URL(fileURLWithPath: args[index + 1]))
          print("Snapshot saved")
        } catch {
          fputs("Snapshot failed\n", stderr)
          exit(1)
        }
        NSApplication.shared.terminate(nil)
      }
      return
    }
    if !args.contains("--demo") { openAtLoginByDefault() }
    popover.behavior = .transient
    popover.animates = true
    let controller = NSHostingController(
      rootView: TrackerView(store: store, showSettings: { [weak self] in self?.showSettings() }))
    popover.contentViewController = controller
    notch = NotchController(store: store, onSettings: { [weak self] in self?.showSettings() })
    store.changed = { [weak self] in self?.applyPlacement() }
    applyPlacement()
    displayObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.applyPlacement() }
    }
    timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.store.refresh() }
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in Task { @MainActor in await self?.store.refresh() } }
    Task { await store.refresh() }
    if args.contains("--window") {
      let window = NSWindow(
        contentViewController: NSHostingController(
          rootView: TrackerView(store: store, showSettings: { [weak self] in self?.showSettings() })
        ))
      window.title = "Notch Sub"
      window.styleMask = [.titled, .closable]
      window.center()
      window.makeKeyAndOrderFront(nil)
      previewWindow = window
      NSApplication.shared.activate(ignoringOtherApps: true)
    } else if args.contains("--settings") {
      showSettings()
    } else if args.contains("--show"), !Placement.current.hasNotch || !hasHardwareNotch {
      togglePopover()
    }
  }
  private func migrateFromSubTracker() {
    guard LegacyStorage.migrate(LocalPaths()) else { return }
    let defaults = UserDefaults.standard
    for (key, value) in defaults.persistentDomain(forName: LegacyStorage.defaultsDomain) ?? [:]
    where defaults.object(forKey: key) == nil {
      defaults.set(value, forKey: key)
    }
  }
  // Once, and only from an Applications folder, so a later choice in Settings sticks and
  // DMG, translocated, or dist/ copies never register themselves.
  private func openAtLoginByDefault() {
    let defaults = UserDefaults.standard
    guard Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications",
      !defaults.bool(forKey: "openAtLoginDefaulted")
    else { return }
    defaults.set(true, forKey: "openAtLoginDefaulted")
    try? SMAppService.mainApp.register()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if Placement.current.hasNotch && hasHardwareNotch {
      notch?.expand()
    } else if !popover.isShown {
      togglePopover()
    }
    return true
  }
  private func applyPlacement() {
    let placement = Placement.current
    let showMenuBar = placement.hasMenuBar || !hasHardwareNotch
    if showMenuBar && item == nil {
      item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      item?.button?.target = self
      item?.button?.action = #selector(togglePopover)
      item?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    } else if !showMenuBar, let item {
      popover.performClose(nil)
      NSStatusBar.system.removeStatusItem(item)
      self.item = nil
    }
    notch?.setVisible(placement.hasNotch && hasHardwareNotch)
    updateStatus()
  }
  @objc private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    notch?.collapse()
    guard let button = item?.button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    NSApplication.shared.activate(ignoringOtherApps: true)
    Task { await store.refresh() }
  }
  private func updateStatus() {
    guard let button = item?.button else { return }
    let symbol = NSImage(
      systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Notch Sub")
    symbol?.isTemplate = true
    button.image = symbol
    button.imagePosition = .imageLeading
    button.title = store.menuTitle.isEmpty ? "" : " \(store.menuTitle)"
    button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    button.toolTip = "Notch Sub · lowest remaining allowance across active accounts"
  }
  private func showSettings() {
    popover.performClose(nil)
    notch?.collapse()
    if settingsWindow == nil {
      let controller = NSHostingController(rootView: SettingsView(store: store))
      let window = NSWindow(contentViewController: controller)
      window.title = "Settings"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      settingsWindow = window
    }
    settingsWindow?.center()
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
