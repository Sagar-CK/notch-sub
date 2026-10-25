import AppKit
import SubTrackerCore
import SwiftUI

enum Placement: String, CaseIterable, Identifiable {
  case notch, menuBar, both
  var id: String { rawValue }
  var title: String {
    switch self {
    case .notch: "Notch"
    case .menuBar: "Menu bar"
    case .both: "Both"
    }
  }
  var hasNotch: Bool { self != .menuBar }
  var hasMenuBar: Bool { self != .notch }
  static var current: Placement {
    Placement(rawValue: UserDefaults.standard.string(forKey: "placement") ?? "notch") ?? .notch
  }
}

private final class NotchWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor final class NotchController: ObservableObject {
  @Published private(set) var expanded = false
  @Published private(set) var cameraWidth: CGFloat = 185
  @Published private(set) var headerHeight: CGFloat = 32
  var wingWidth: CGFloat { store.accounts.filter(\.isActive).count > 2 ? 112 : 70 }
  var expandedWidth: CGFloat { max(382, cameraWidth + wingWidth * 2) }
  private var panel: NotchWindow!
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var screenObserver: NSObjectProtocol?
  private var visible = false
  private let store: TrackerStore
  private let onSettings: () -> Void

  init(store: TrackerStore, onSettings: @escaping () -> Void) {
    self.store = store
    self.onSettings = onSettings
    panel = NotchWindow(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.title = "Sub Tracker"
    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.contentView = NSHostingView(
      rootView: NotchView(store: store, controller: self, onSettings: onSettings))
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.position(animated: false) }
    }
  }
  func setVisible(_ value: Bool) {
    guard value != visible else {
      if value { position(animated: false) }
      return
    }
    visible = value
    if value {
      position(animated: false)
      panel.orderFrontRegardless()
    } else {
      collapse()
      panel.orderOut(nil)
    }
  }
  func toggle() { expanded ? collapse() : expand() }
  func expand() {
    guard visible, !expanded else { return }
    expanded = true
    panel.hasShadow = true
    position(animated: false)
    panel.makeKeyAndOrderFront(nil)
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] _ in
      Task { @MainActor in if self?.panel.attachedSheet == nil { self?.collapse() } }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .keyDown,
    ]) { [weak self] event in
      guard let self else { return event }
      if event.type == .keyDown, event.keyCode == 53, self.panel.attachedSheet == nil {
        self.collapse()
        return nil
      }
      if event.type != .keyDown, event.window != self.panel, self.panel.attachedSheet == nil {
        self.collapse()
      }
      return event
    }
    Task { await store.refresh() }
  }
  func collapse() {
    guard expanded else { return }
    expanded = false
    panel.hasShadow = false
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    position(animated: false)
  }
  private func position(animated: Bool) {
    guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { return }
    let center: CGFloat
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
      center = (left.maxX + right.minX) / 2
      cameraWidth = right.minX - left.maxX
    } else {
      center = screen.frame.midX
    }
    headerHeight = screen.safeAreaInsets.top
    // The collapsed panel occupies the real menu-bar band, leaving the physical camera cutout empty.
    let top = screen.frame.maxY
    let width: CGFloat = expanded ? expandedWidth : cameraWidth + wingWidth * 2
    let height: CGFloat =
      expanded ? min(576 + headerHeight, screen.visibleFrame.height - 40) : headerHeight
    panel.setFrame(
      NSRect(x: center - width / 2, y: top - height, width: width, height: height), display: true,
      animate: animated)
  }
}

private struct NotchView: View {
  @ObservedObject var store: TrackerStore
  @ObservedObject var controller: NotchController
  let onSettings: () -> Void
  private var active: [Account] { store.accounts.filter(\.isActive) }
  var body: some View {
    VStack(spacing: 0) {
      Button {
        controller.toggle()
      } label: {
        HStack(spacing: 0) {
          HStack(spacing: 10) {
            if active.isEmpty {
              Image(systemName: "chart.bar.xaxis").foregroundStyle(.white.opacity(0.8))
            }
            ForEach(active.prefix(active.count > 3 ? 2 : 1)) { account in readout(account) }
          }.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10)
          Color.clear.frame(width: controller.cameraWidth)
          HStack(spacing: 10) {
            ForEach(active.dropFirst(active.count > 3 ? 2 : 1).prefix(active.count > 4 ? 1 : 2)) {
              account in readout(account)
            }
            if active.count > 4 {
              Text("+\(active.count - 3)").font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .help("\(active.count - 3) more providers")
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
        }.frame(maxWidth: .infinity).frame(height: controller.headerHeight).contentShape(
          Rectangle())
      }.buttonStyle(.plain).accessibilityLabel(
        controller.expanded ? "Collapse usage" : "Expand usage"
      )
      .help("Remaining allowance · click for accounts")
      if controller.expanded {
        TrackerView(store: store, showSettings: onSettings, width: controller.expandedWidth)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(controller.expanded ? Color.black : Color.clear)
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: 0, bottomLeadingRadius: controller.expanded ? 18 : 0,
        bottomTrailingRadius: controller.expanded ? 18 : 0, topTrailingRadius: 0)
    )
    .environment(\.colorScheme, .dark)
  }
  private func readout(_ account: Account) -> some View {
    HStack(spacing: 5) {
      ProviderIcon(provider: account.provider, size: 12)
      let remaining = account.usage?.windows.map(\.remainingPercent).min()
      Text(
        account.issue == nil && account.usage?.isStale() == false
          ? remaining.map { "\(Int($0))%" } ?? "?" : "?"
      )
      .font(.system(size: 10, weight: .medium)).monospacedDigit()
    }.foregroundStyle(.white.opacity(0.85)).fixedSize()
  }
}
