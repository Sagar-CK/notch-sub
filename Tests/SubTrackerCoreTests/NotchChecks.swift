import SubTrackerCore

extension SubTrackerCoreTests {
  static var notchChecks: [(String, (SubTrackerCoreTests) throws -> Void)] {
    [
      ("Notch ignores brief passes and closes after leaving", { $0.testNotchHover() }),
      ("Notch reentry cancels dismissal", { $0.testNotchReentry() }),
      ("Notch click stays open and Escape suppresses reopening", { $0.testNotchPinAndDismiss() }),
      ("Notch does not dismiss menus or sheets", { $0.testNotchInteractionHold() }),
    ]
  }

  func testNotchHover() {
    var notch = NotchInteraction()
    notch.pointerChanged(inside: true, at: 0)
    notch.advance(at: 0.1)
    expect(!notch.isExpanded)
    notch.pointerChanged(inside: false, at: 0.11)
    notch.advance(at: 1)
    expect(!notch.isExpanded)
    notch.pointerChanged(inside: true, at: 2)
    notch.advance(at: 2.3)
    expect(!notch.isExpanded)
    notch.advance(at: 2.36)
    expectEqual(notch.presentation, .hover)
    notch.pointerChanged(inside: false, at: 3)
    notch.advance(at: 3.2)
    expect(notch.isExpanded)
    notch.advance(at: 3.4)
    expect(!notch.isExpanded)
    expectNil(notch.deadline)
  }

  func testNotchReentry() {
    var notch = NotchInteraction()
    notch.pointerChanged(inside: true, at: 0)
    notch.advance(at: 1)
    notch.pointerChanged(inside: false, at: 2)
    notch.pointerChanged(inside: true, at: 2.2)
    notch.advance(at: 3)
    expectEqual(notch.presentation, .hover)
    expectNil(notch.deadline)
  }

  func testNotchPinAndDismiss() {
    var notch = NotchInteraction()
    notch.pointerChanged(inside: true, at: 0)
    notch.advance(at: 1)
    notch.clickHeader()
    expectEqual(notch.presentation, .pinned)
    notch.pointerChanged(inside: false, at: 2)
    notch.advance(at: 10)
    expect(notch.isExpanded)
    notch.clickHeader()
    expect(!notch.isExpanded)
    notch.pointerChanged(inside: true, at: 11)
    notch.advance(at: 12)
    expect(notch.isExpanded)
    notch.dismiss()
    notch.pointerChanged(inside: true, at: 13)
    notch.advance(at: 14)
    expect(!notch.isExpanded)
    notch.pointerChanged(inside: false, at: 15)
    notch.pointerChanged(inside: true, at: 16)
    notch.advance(at: 17)
    expect(notch.isExpanded)
    notch = NotchInteraction()  // Changing placement or disconnecting the screen clears state.
    expect(!notch.isExpanded)
    expectNil(notch.deadline)
    notch.clickHeader()
    expectEqual(notch.presentation, .pinned)
  }

  func testNotchInteractionHold() {
    var notch = NotchInteraction()
    notch.pointerChanged(inside: true, at: 0)
    notch.advance(at: 1)
    notch.pointerChanged(inside: false, at: 2)
    notch.advance(at: 3, interactionInProgress: true)
    expect(notch.isExpanded)
    notch.advance(at: 4, interactionInProgress: true)
    expect(notch.isExpanded)
    notch.advance(at: 5)
    expect(!notch.isExpanded)
    notch.pin()
    notch.advance(at: 6)
    expectEqual(notch.presentation, .pinned)
  }
}
