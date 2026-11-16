import XCTest
@testable import GlassDock

final class PinWindowTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)

    func testHalvesSplitTheVisibleFrameWithoutGap() {
        XCTAssertEqual(SnapPreset.leftHalf.frame(in: visible), CGRect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(SnapPreset.rightHalf.frame(in: visible), CGRect(x: 720, y: 25, width: 720, height: 875))
    }

    func testOddSizesGiveTheLeftoverPixelToTheRightAndBottom() {
        let odd = CGRect(x: 10, y: 20, width: 101, height: 51)
        XCTAssertEqual(SnapPreset.leftHalf.frame(in: odd).maxX, SnapPreset.rightHalf.frame(in: odd).minX)
        XCTAssertEqual(SnapPreset.rightHalf.frame(in: odd).maxX, odd.maxX)
        XCTAssertEqual(SnapPreset.topLeft.frame(in: odd).maxY, SnapPreset.bottomLeft.frame(in: odd).minY)
        XCTAssertEqual(SnapPreset.bottomRight.frame(in: odd).maxY, odd.maxY)
    }

    func testQuartersSitInTheirCorners() {
        XCTAssertEqual(SnapPreset.topLeft.frame(in: visible), CGRect(x: 0, y: 25, width: 720, height: 437))
        XCTAssertEqual(SnapPreset.topRight.frame(in: visible), CGRect(x: 720, y: 25, width: 720, height: 437))
        XCTAssertEqual(SnapPreset.bottomLeft.frame(in: visible), CGRect(x: 0, y: 462, width: 720, height: 438))
        XCTAssertEqual(SnapPreset.bottomRight.frame(in: visible), CGRect(x: 720, y: 462, width: 720, height: 438))
    }

    func testCenterIsSixtyPercentAndCentered() {
        let frame = SnapPreset.center.frame(in: visible)
        XCTAssertEqual(frame.width, 864)
        XCTAssertEqual(frame.height, 525)
        XCTAssertEqual(frame.midX, visible.midX)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.5)
    }

    func testMaximizeFillsTheVisibleFrameNotTheScreen() {
        XCTAssertEqual(SnapPreset.maximize.frame(in: visible), visible)
    }

    func testFlipConvertsAScreenBelowTheMenuBarToTopLeftOrigin() {
        let cocoa = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(WindowGeometry.flipped(cocoa, primaryHeight: 900), CGRect(x: 0, y: 25, width: 1440, height: 875))
    }

    func testFlipIsItsOwnInverse() {
        let rect = CGRect(x: -300, y: 120, width: 640, height: 480)
        XCTAssertEqual(WindowGeometry.flipped(WindowGeometry.flipped(rect, primaryHeight: 900), primaryHeight: 900), rect)
    }

    func testDisplayAboveTheMainOneHasNegativeY() {
        let above = DisplayArea(cocoaFrame: CGRect(x: 0, y: 900, width: 1920, height: 1080),
                                cocoaVisibleFrame: CGRect(x: 0, y: 900, width: 1920, height: 1055), primaryHeight: 900)
        XCTAssertEqual(above.frame, CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        XCTAssertEqual(above.visibleFrame, CGRect(x: 0, y: -1080 + 25, width: 1920, height: 1055))
    }

    func testDisplayLeftOfTheMainOneKeepsItsNegativeXAndAlignsAtTheBottom() {
        let left = DisplayArea(cocoaFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                               cocoaVisibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055), primaryHeight: 900)
        XCTAssertEqual(left.frame, CGRect(x: -1920, y: -180, width: 1920, height: 1080))
        XCTAssertEqual(left.visibleFrame, CGRect(x: -1920, y: -155, width: 1920, height: 1055))
    }

    func testSnapOnADisplayAboveUsesThatDisplaysCoordinates() {
        let above = DisplayArea(cocoaFrame: CGRect(x: 0, y: 900, width: 1920, height: 1080),
                                cocoaVisibleFrame: CGRect(x: 0, y: 900, width: 1920, height: 1055), primaryHeight: 900)
        XCTAssertEqual(SnapPreset.topLeft.frame(in: above.visibleFrame), CGRect(x: 0, y: -1055, width: 960, height: 527))
    }

    func testDisplayIndexPicksTheDisplayWithMostOfTheWindow() {
        let main = DisplayArea(cocoaFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                               cocoaVisibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875), primaryHeight: 900)
        let above = DisplayArea(cocoaFrame: CGRect(x: 0, y: 900, width: 1920, height: 1080),
                                cocoaVisibleFrame: CGRect(x: 0, y: 900, width: 1920, height: 1055), primaryHeight: 900)
        let areas = [main, above]
        XCTAssertEqual(WindowGeometry.displayIndex(for: CGRect(x: 100, y: 100, width: 400, height: 300), among: areas), 0)
        XCTAssertEqual(WindowGeometry.displayIndex(for: CGRect(x: 100, y: -500, width: 400, height: 300), among: areas), 1)
        XCTAssertEqual(WindowGeometry.displayIndex(for: CGRect(x: 100, y: -150, width: 400, height: 300), among: areas), 0)
    }

    func testDisplayIndexFallsBackToTheNearestDisplayAndHandlesNone() {
        let main = DisplayArea(cocoaFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                               cocoaVisibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), primaryHeight: 800)
        let right = DisplayArea(cocoaFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
                                cocoaVisibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800), primaryHeight: 800)
        XCTAssertEqual(WindowGeometry.displayIndex(for: CGRect(x: 2500, y: 100, width: 200, height: 200), among: [main, right]), 1)
        XCTAssertNil(WindowGeometry.displayIndex(for: .zero, among: []))
    }

    func testMovingToAnotherDisplayKeepsRelativePositionAndSize() {
        let source = CGRect(x: 0, y: 25, width: 1000, height: 800)
        let target = CGRect(x: 1000, y: -1080, width: 2000, height: 1600)
        let moved = WindowGeometry.moved(CGRect(x: 500, y: 425, width: 250, height: 200), from: source, to: target)
        XCTAssertEqual(moved, CGRect(x: 2000, y: -280, width: 500, height: 400))
    }

    func testMovedWindowIsClampedInsideTheTargetDisplay() {
        let source = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let target = CGRect(x: 2000, y: 0, width: 1000, height: 500)
        let moved = WindowGeometry.moved(CGRect(x: 1900, y: 900, width: 600, height: 400), from: source, to: target)
        XCTAssertTrue(target.contains(moved))
    }

    func testFilterAcceptsAnOrdinaryWindowOfAnotherApp() {
        XCTAssertTrue(WindowFilter.isNormal(WindowCandidate(pid: 10, layer: 0, frame: CGRect(x: 0, y: 0, width: 800, height: 600)), ownPID: 99))
    }

    func testFilterRejectsOwnAppNonZeroLayerAndTinyWindows() {
        let big = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertFalse(WindowFilter.isNormal(WindowCandidate(pid: 99, layer: 0, frame: big), ownPID: 99))
        XCTAssertFalse(WindowFilter.isNormal(WindowCandidate(pid: 10, layer: 25, frame: big), ownPID: 99))
        XCTAssertFalse(WindowFilter.isNormal(WindowCandidate(pid: 10, layer: -20, frame: big), ownPID: 99))
        XCTAssertFalse(WindowFilter.isNormal(WindowCandidate(pid: 10, layer: 0, frame: CGRect(x: 0, y: 0, width: 40, height: 600)), ownPID: 99))
        XCTAssertFalse(WindowFilter.isNormal(WindowCandidate(pid: 10, layer: 0, frame: CGRect(x: 0, y: 0, width: 800, height: 20)), ownPID: 99))
    }

    func testPinnedWindowsListFirstInPinOrder() {
        XCTAssertEqual(PinPolicy.pinnedFirst(["a", "b", "c", "d"], pinned: ["c", "a"]), ["c", "a", "b", "d"])
    }

    func testPinnedWindowsThatNoLongerExistAreSkippedInTheList() {
        XCTAssertEqual(PinPolicy.pinnedFirst(["a", "b"], pinned: ["x", "b"]), ["b", "a"])
        XCTAssertEqual(PinPolicy.pinnedFirst(["a", "b"], pinned: []), ["a", "b"])
    }

    private let area = CGRect(x: 0, y: 0, width: 500, height: 500)

    private func entry(_ id: Int, owner: Int32? = nil, _ frame: CGRect) -> (id: Int, owner: Int32, frame: CGRect) {
        (id: id, owner: owner ?? Int32(id), frame: frame)
    }

    func testNoRaiseWhenThePinnedWindowIsOnTop() {
        let z = [entry(1, area), entry(2, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [1]), [])
    }

    func testRaiseWhenAnOverlappingWindowOfAnotherAppIsInFront() {
        let z = [entry(2, area), entry(1, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [1]), [1])
    }

    func testRaiseWhenAnotherAppCoversOnlyPartOfThePinnedWindow() {
        let z = [entry(2, CGRect(x: 400, y: 400, width: 300, height: 300)), entry(1, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [1]), [1])
    }

    func testNoRaiseWhenOnlyAnotherWindowOfTheSameAppIsInFront() {
        let z = [entry(2, owner: 7, area), entry(1, owner: 7, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [1]), [])
    }

    func testRaiseWhenAnotherAppIsInFrontEvenIfASameAppWindowIsAlsoThere() {
        let z = [entry(3, owner: 8, area), entry(2, owner: 7, area), entry(1, owner: 7, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [1]), [1])
    }

    func testNoRaiseWhenTheFrontWindowDoesNotOverlap() {
        let z = [entry(2, CGRect(x: 600, y: 0, width: 300, height: 300)), entry(1, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [1]), [])
    }

    func testWindowsTouchingOnlyAtAnEdgeDoNotOverlap() {
        let z = [entry(2, CGRect(x: 500, y: 0, width: 300, height: 300)), entry(1, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [1]), [])
    }

    func testPinnedWindowNotOnScreenIsIgnored() {
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: [entry(2, area)], pinned: [1]), [])
    }

    func testTheMostRecentlyPinnedWindowMustEndOnTop() {
        let z = [entry(1, area), entry(2, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [2, 1]), [2])
    }

    func testCorrectPinnedOrderNeedsNoRaise() {
        let z = [entry(2, area), entry(1, area), entry(3, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [2, 1]), [])
    }

    func testRaiseKeepsHigherPriorityPinnedWindowsOnTopOfTheRaisedOne() {
        let z = [entry(3, area), entry(2, area), entry(1, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [2, 1]), [1, 2])
    }

    func testRaiseOnlyCoversPinnedWindowsOnScreen() {
        let z = [entry(3, area), entry(1, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [2, 1]), [1])
    }

    func testTwoPinnedWindowsOfOneAppAreOrderedByPinRecency() {
        let z = [entry(1, owner: 7, area), entry(2, owner: 7, area)]
        XCTAssertEqual(PinPolicy.windowsToRaise(zOrder: z, pinned: [2, 1]), [2])
    }

    func testNoButtonHeldIsNeverADrag() {
        XCTAssertFalse(PinPolicy.isDragging(heldFor: nil, travel: 500))
    }

    func testAPlainClickIsNotADrag() {
        XCTAssertFalse(PinPolicy.isDragging(heldFor: 0, travel: 0))
        XCTAssertFalse(PinPolicy.isDragging(heldFor: 0.05, travel: PinPolicy.dragDistance))
        XCTAssertFalse(PinPolicy.isDragging(heldFor: PinPolicy.dragHoldDuration, travel: 1))
    }

    func testMovingThePointerFarEnoughIsADrag() {
        XCTAssertTrue(PinPolicy.isDragging(heldFor: 0.05, travel: PinPolicy.dragDistance + 1))
    }

    func testHoldingTheButtonLongIsADragEvenWithoutMoving() {
        XCTAssertTrue(PinPolicy.isDragging(heldFor: PinPolicy.dragHoldDuration + 0.01, travel: 0))
    }

    func testRaiseAllowedDuringAPlainClick() {
        XCTAssertTrue(PinPolicy.canRaise(secondsSinceLastRaise: nil, mouseHeldFor: 0.03, mouseTravel: 1, isIslandInUse: false))
    }

    func testNoRaiseWhileDragging() {
        XCTAssertFalse(PinPolicy.canRaise(secondsSinceLastRaise: nil, mouseHeldFor: 0.1, mouseTravel: 50, isIslandInUse: false))
        XCTAssertFalse(PinPolicy.canRaise(secondsSinceLastRaise: 10, mouseHeldFor: 1, mouseTravel: 0, isIslandInUse: false))
    }

    func testNoRaiseWhileTheIslandIsInUse() {
        XCTAssertFalse(PinPolicy.canRaise(secondsSinceLastRaise: nil, mouseHeldFor: nil, mouseTravel: 0, isIslandInUse: true))
        XCTAssertFalse(PinPolicy.canRaise(secondsSinceLastRaise: 10, mouseHeldFor: nil, mouseTravel: 0, isIslandInUse: true))
    }

    func testRaiseIsDebouncedAfterTheLastRaise() {
        XCTAssertFalse(PinPolicy.canRaise(secondsSinceLastRaise: 0.05, mouseHeldFor: nil, mouseTravel: 0, isIslandInUse: false))
        XCTAssertTrue(PinPolicy.canRaise(secondsSinceLastRaise: PinPolicy.minimumRaiseInterval, mouseHeldFor: nil, mouseTravel: 0,
                                         isIslandInUse: false))
        XCTAssertTrue(PinPolicy.canRaise(secondsSinceLastRaise: nil, mouseHeldFor: nil, mouseTravel: 0, isIslandInUse: false))
    }

    func testTheRaiseDebounceStaysShort() {
        XCTAssertLessThanOrEqual(PinPolicy.minimumRaiseInterval, 0.1)
    }

    private func onScreen(_ id: CGWindowID, pid: Int32, layer: Int = 0, _ frame: CGRect) -> OnScreenWindow {
        OnScreenWindow(id: id, candidate: WindowCandidate(pid: pid, layer: layer, frame: frame))
    }

    func testFrameFallbackMatchesTheSameAppWindowWithinTolerance() {
        let windows = [onScreen(5, pid: 2, area), onScreen(6, pid: 1, CGRect(x: 1, y: -1, width: 502, height: 499))]
        XCTAssertEqual(PinPolicy.windowID(matching: area, pid: 1, among: windows), 6)
    }

    func testFrameFallbackIgnoresOtherFramesLayersAndApps() {
        let windows = [onScreen(5, pid: 2, area), onScreen(6, pid: 1, layer: 25, area),
                       onScreen(7, pid: 1, CGRect(x: 20, y: 0, width: 500, height: 500))]
        XCTAssertNil(PinPolicy.windowID(matching: area, pid: 1, among: windows))
    }

    func testFrameFallbackPrefersTheClosestFrameThenTheFrontmost() {
        let near = CGRect(x: 2, y: 0, width: 500, height: 500)
        XCTAssertEqual(PinPolicy.windowID(matching: area, pid: 1, among: [onScreen(5, pid: 1, near), onScreen(6, pid: 1, area)]), 6)
        XCTAssertEqual(PinPolicy.windowID(matching: area, pid: 1, among: [onScreen(5, pid: 1, area), onScreen(6, pid: 1, area)]), 5)
    }

    func testFrameFallbackSkipsWindowsAlreadyClaimedByAnotherPin() {
        let windows = [onScreen(5, pid: 1, area), onScreen(6, pid: 1, area)]
        XCTAssertEqual(PinPolicy.windowID(matching: area, pid: 1, among: windows, excluding: [5]), 6)
        XCTAssertNil(PinPolicy.windowID(matching: area, pid: 1, among: windows, excluding: [5, 6]))
    }
}
