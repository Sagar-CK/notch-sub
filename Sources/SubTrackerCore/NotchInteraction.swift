import Foundation

/// The pointer and dismissal rules, independent of AppKit and wall-clock changes.
public struct NotchInteraction {
  public enum Presentation: Equatable { case closed, hover, pinned }
  public private(set) var presentation: Presentation = .closed
  public private(set) var pointerInside = false
  public private(set) var deadline: TimeInterval?
  private var suppressedUntilExit = false
  public var isExpanded: Bool { presentation != .closed }

  public init() {}

  public mutating func pointerChanged(inside: Bool, at time: TimeInterval) {
    guard inside != pointerInside else { return }
    pointerInside = inside
    if inside {
      deadline = presentation == .closed && !suppressedUntilExit ? time + 0.14 : nil
    } else {
      suppressedUntilExit = false
      deadline = presentation == .hover ? time + 0.32 : nil
    }
  }

  public mutating func advance(at time: TimeInterval, interactionInProgress: Bool = false) {
    guard let deadline, time >= deadline else { return }
    if pointerInside, presentation == .closed, !suppressedUntilExit {
      presentation = .hover
      self.deadline = nil
    } else if !pointerInside, presentation == .hover {
      if interactionInProgress {
        self.deadline = time + 0.1
      } else {
        presentation = .closed
        self.deadline = nil
      }
    } else {
      self.deadline = nil
    }
  }

  public mutating func pin() {
    presentation = .pinned
    deadline = nil
  }

  public mutating func clickHeader() {
    if presentation == .pinned { dismiss() } else { pin() }
  }

  public mutating func dismiss() {
    presentation = .closed
    deadline = nil
    // Escape or a click must not immediately reopen the panel under a stationary pointer.
    suppressedUntilExit = pointerInside
  }
}
