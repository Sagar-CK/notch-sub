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

private final class NotchHostingView: NSHostingView<NotchView> {
  var pointerChanged: (() -> Void)?
  private var hoverArea: NSTrackingArea?

  override func updateTrackingAreas() {
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
    super.updateTrackingAreas()
  }
  override func mouseEntered(with event: NSEvent) { pointerChanged?() }
  override func mouseExited(with event: NSEvent) { pointerChanged?() }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class NotchController: ObservableObject {
  @Published private(set) var expanded = false
  @Published private(set) var pinned = false
  @Published private(set) var surfaceVisible = false
  @Published private(set) var cameraWidth: CGFloat = 0
  @Published private(set) var headerHeight: CGFloat = 0
  @Published private(set) var expandedHeight: CGFloat = 0
  var expandedWidth: CGFloat { max(410, cameraWidth + 60) }
  private var panel: NotchWindow!
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var observers: [NSObjectProtocol] = []
  private var hoverTask: Task<Void, Never>?
  private var menuTracking = false
  private var interaction = NotchInteraction()
  private var animationID = 0
  private var visible = false
  private var collapsedFrame = NSRect.zero
  private var expandedFrame = NSRect.zero
  private let store: TrackerStore
  private let onSettings: () -> Void
  private var interactionInProgress: Bool { menuTracking || panel.attachedSheet != nil }
  private var hitFrame: NSRect { expanded ? expandedFrame : collapsedFrame }

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
    panel.acceptsMouseMovedEvents = true
    panel.appearance = NSAppearance(named: .darkAqua)
    let view = NotchHostingView(
      rootView: NotchView(store: store, controller: self, onSettings: onSettings))
    view.sizingOptions = []
    view.pointerChanged = { [weak self] in self?.updatePointer() }
    panel.contentView = view
    observe(NSApplication.didChangeScreenParametersNotification) { $0.position(animated: false) }
    observe(NSMenu.didBeginTrackingNotification) { $0.menuTracking = true }
    observe(NSMenu.didEndTrackingNotification) {
      $0.menuTracking = false
      $0.updatePointer()
    }
  }

  private func observe(_ name: Notification.Name, action: @escaping (NotchController) -> Void) {
    observers.append(
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in
        Task { @MainActor in if let self { action(self) } }
      })
  }

  func setVisible(_ value: Bool) {
    guard value != visible else {
      if value { position(animated: true) }
      return
    }
    visible = value
    if value {
      position(animated: false)
      panel.orderFrontRegardless()
      installMonitors()
      updatePointer()
    } else {
      interaction = NotchInteraction()
      hoverTask?.cancel()
      removeMonitors()
      animationID += 1
      expanded = false
      pinned = false
      surfaceVisible = false
      panel.orderOut(nil)
    }
  }

  func toggle() {
    guard visible else { return }
    interaction.clickHeader()
    applyInteraction()
  }

  func expand() {
    guard visible else { return }
    interaction.pin()
    applyInteraction()
  }

  func collapse() {
    interaction.dismiss()
    applyInteraction()
  }

  private func updatePointer() {
    guard visible else { return }
    let inside = hitFrame.contains(NSEvent.mouseLocation)
    // The larger animation canvas must not intercept apps below its transparent area.
    panel.ignoresMouseEvents = !inside
    interaction.pointerChanged(inside: inside, at: ProcessInfo.processInfo.systemUptime)
    scheduleHover()
  }

  private func scheduleHover() {
    hoverTask?.cancel()
    guard visible, let deadline = interaction.deadline else { return }
    let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
    hoverTask = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
      guard let self, self.visible else { return }
      self.interaction.advance(
        at: ProcessInfo.processInfo.systemUptime, interactionInProgress: self.interactionInProgress)
      self.applyInteraction()
    }
  }

  private func applyInteraction() {
    let newPinned = interaction.presentation == .pinned
    if pinned != newPinned { pinned = newPinned }
    let opening = interaction.isExpanded && !expanded
    position(animated: true)
    if pinned {
      panel.makeKeyAndOrderFront(nil)
    } else if !expanded {
      panel.resignKey()
    }
    if opening {
      // Hover reveals usage without taking keyboard focus from the current app.
      panel.orderFrontRegardless()
      Task { await store.refresh() }
    }
    scheduleHover()
  }

  private func installMonitors() {
    // Mouse-only global monitoring also reaches the transparent physical cutout.
    // It does not require Accessibility permission or observe keyboard input.
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .mouseMoved, .leftMouseDown, .rightMouseDown,
    ]) { [weak self] event in
      Task { @MainActor in
        guard let self else { return }
        if event.type == .mouseMoved {
          self.updatePointer()
        } else if !self.interactionInProgress {
          let point = NSEvent.mouseLocation
          if self.hitFrame.contains(point) {
            if !self.expanded || point.y >= self.expandedFrame.maxY - self.headerHeight {
              self.toggle()
            } else {
              self.expand()
            }
          } else if self.expanded {
            self.collapse()
          }
        }
      }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown,
    ]) { [weak self] event in
      guard let self else { return event }
      if event.type == .mouseMoved {
        self.updatePointer()
        return event
      }
      guard self.expanded, !self.interactionInProgress else { return event }
      if event.type == .keyDown, event.keyCode == 53 {
        self.collapse()
        return nil
      }
      if event.type != .keyDown {
        if event.window != self.panel {
          self.collapse()
        } else if event.locationInWindow.y < self.panel.frame.height - self.headerHeight {
          self.expand()
        }
      }
      return event
    }
  }

  private func removeMonitors() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    globalMonitor = nil
    localMonitor = nil
  }

  private func position(animated: Bool) {
    guard visible,
      let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
      let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea
    else { return }
    let center = (left.maxX + right.minX) / 2
    let newCameraWidth = right.minX - left.maxX
    let newHeaderHeight = screen.safeAreaInsets.top
    let width = max(410, newCameraWidth + 60)
    let willExpand = interaction.isExpanded
    let contentHeight =
      willExpand
      ? NSHostingView(
        rootView: TrackerView(
          store: store, showSettings: onSettings, width: width, background: .black)
      ).fittingSize.height : max(200, expandedHeight - newHeaderHeight)
    let height = min(max(200, contentHeight) + newHeaderHeight, screen.visibleFrame.height - 40)
    let nextExpandedFrame = NSRect(
      x: center - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    // Only the hit area extends beyond the hardware. No extra notch is drawn.
    collapsedFrame = NSRect(
      x: center - (newCameraWidth + 12) / 2, y: screen.frame.maxY - newHeaderHeight - 4,
      width: newCameraWidth + 12, height: newHeaderHeight + 4)
    let changed =
      expanded != willExpand || expandedFrame != nextExpandedFrame
      || cameraWidth != newCameraWidth || headerHeight != newHeaderHeight
    expandedFrame = nextExpandedFrame
    guard changed else { return }
    if cameraWidth != newCameraWidth { cameraWidth = newCameraWidth }
    if headerHeight != newHeaderHeight { headerHeight = newHeaderHeight }
    animationID += 1
    let currentAnimation = animationID
    let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if willExpand || surfaceVisible {
      // Hold the native window still while SwiftUI animates the surface inside it.
      // Shrinking NSWindow itself makes SwiftUI relayout every animation frame.
      let canvasHeight = max(height, panel.frame.height)
      panel.setFrame(
        NSRect(
          x: center - width / 2, y: screen.frame.maxY - canvasHeight,
          width: width, height: canvasHeight), display: true)
      panel.contentView?.layoutSubtreeIfNeeded()
      surfaceVisible = true
    }
    let motion: Animation? =
      shouldAnimate
      ? .spring(response: willExpand ? 0.36 : 0.4, dampingFraction: willExpand ? 0.86 : 1)
      : nil
    withAnimation(motion, completionCriteria: .removed) {
      expandedHeight = height
      expanded = willExpand
    } completion: { [weak self] in
      Task { @MainActor in
        guard let self, self.visible, self.animationID == currentAnimation else { return }
        self.panel.setFrame(self.expanded ? self.expandedFrame : self.collapsedFrame, display: true)
        if !self.expanded { self.surfaceVisible = false }
        self.updatePointer()
      }
    }
    if !surfaceVisible { panel.setFrame(collapsedFrame, display: true) }
  }
}

private struct NotchView: View {
  @ObservedObject var store: TrackerStore
  @ObservedObject var controller: NotchController
  let onSettings: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { _ in
      ZStack(alignment: .top) {
        Color.black
        VStack(spacing: 0) {
          Button(action: controller.toggle) {
            Color.clear.frame(height: controller.headerHeight).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(controller.pinned ? "Collapse usage" : "Keep usage open")
          TrackerView(
            store: store, showSettings: onSettings, width: controller.expandedWidth,
            background: .black)
        }
        .frame(width: controller.expandedWidth, height: controller.expandedHeight, alignment: .top)
        .scaleEffect(controller.expanded || reduceMotion ? 1 : 0.96, anchor: .top)
        .opacity(controller.expanded ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: controller.expanded)
        .allowsHitTesting(controller.expanded)
        .accessibilityHidden(!controller.expanded)
      }
      .frame(
        width: controller.expanded ? controller.expandedWidth : controller.cameraWidth,
        height: controller.expanded ? controller.expandedHeight : controller.headerHeight,
        alignment: .top
      )
      .clipShape(
        UnevenRoundedRectangle(
          topLeadingRadius: 0, bottomLeadingRadius: controller.expanded ? 24 : 10,
          bottomTrailingRadius: controller.expanded ? 24 : 10, topTrailingRadius: 0)
      )
      .opacity(controller.surfaceVisible ? 1 : 0)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .overlay(alignment: .top) {
        if !controller.expanded {
          Button(action: controller.toggle) {
            Color.clear.frame(
              width: controller.cameraWidth + 12, height: controller.headerHeight + 4
            )
            .contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityLabel("Open usage")
        }
      }
    }
    .environment(\.colorScheme, .dark)
  }
}
