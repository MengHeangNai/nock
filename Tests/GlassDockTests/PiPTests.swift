import AppKit
import ScreenCaptureKit
import XCTest
@testable import GlassDock

final class PiPTests: XCTestCase {
    func testAspectIsWidthOverHeightAndNilForEmptySizes() {
        XCTAssertEqual(PiPGeometry.aspect(of: CGSize(width: 1600, height: 900)) ?? 0, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertNil(PiPGeometry.aspect(of: CGSize(width: 0, height: 900)))
        XCTAssertNil(PiPGeometry.aspect(of: CGSize(width: 800, height: -1)))
    }

    func testAspectChangeNeedsMoreThanOnePercent() {
        XCTAssertFalse(PiPGeometry.hasAspectChanged(from: 1.6, to: 1.61))
        XCTAssertTrue(PiPGeometry.hasAspectChanged(from: 1.6, to: 1.7))
        XCTAssertTrue(PiPGeometry.hasAspectChanged(from: 1.6, to: 1.5))
    }

    func testFittedSizeKeepsTheAspect() {
        let size = PiPGeometry.fittedSize(width: 320, aspect: 16.0 / 9.0, within: CGSize(width: 1440, height: 875))
        XCTAssertEqual(size, CGSize(width: 320, height: 180))
    }

    func testFittedSizeClampsToTheMinimumWidth() {
        let size = PiPGeometry.fittedSize(width: 50, aspect: 2, within: CGSize(width: 1440, height: 875))
        XCTAssertEqual(size, CGSize(width: PiPGeometry.minimumWidth, height: PiPGeometry.minimumWidth / 2))
    }

    func testFittedSizeShrinksATallWindowToTheDisplayHeight() {
        let size = PiPGeometry.fittedSize(width: 480, aspect: 0.5, within: CGSize(width: 1440, height: 400))
        XCTAssertEqual(size, CGSize(width: 200, height: 400))
    }

    func testFittedSizeShrinksToTheDisplayWidth() {
        let size = PiPGeometry.fittedSize(width: 480, aspect: 2, within: CGSize(width: 300, height: 875))
        XCTAssertEqual(size, CGSize(width: 300, height: 150))
    }

    func testSizePresetsGrowFromSmallToLarge() {
        XCTAssertEqual(PiPSizePreset.allCases.map(\.width), [240, 320, 480])
        XCTAssertEqual(PiPGeometry.defaultWidth, 320)
    }

    func testCaptureSizeScalesByTheBackingScale() {
        XCTAssertEqual(PiPGeometry.captureSize(windowSize: CGSize(width: 800, height: 600), scale: 2),
                       CGSize(width: 1600, height: 1200))
        XCTAssertEqual(PiPGeometry.captureSize(windowSize: CGSize(width: 800.5, height: 600), scale: 1),
                       CGSize(width: 801, height: 600))
    }

    func testInitialFrameSitsInTheBottomRightOfTheVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frame = PiPGeometry.initialFrame(size: CGSize(width: 320, height: 180), in: visible, cascade: 0)
        XCTAssertEqual(frame, CGRect(x: 1440 - 20 - 320, y: 20, width: 320, height: 180))
    }

    func testInitialFrameFollowsADisplayToTheRightAndAbove() {
        let visible = CGRect(x: 1440, y: 900, width: 1920, height: 1055)
        let frame = PiPGeometry.initialFrame(size: CGSize(width: 320, height: 180), in: visible, cascade: 0)
        XCTAssertEqual(frame.origin, CGPoint(x: 3360 - 20 - 320, y: 920))
    }

    func testLaterPiPsCascadeUpAndLeftAndStayOnTheDisplay() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let size = CGSize(width: 320, height: 180)
        let first = PiPGeometry.initialFrame(size: size, in: visible, cascade: 0)
        let second = PiPGeometry.initialFrame(size: size, in: visible, cascade: 1)
        XCTAssertEqual(second.minX, first.minX - PiPGeometry.cascadeStep)
        XCTAssertEqual(second.minY, first.minY + PiPGeometry.cascadeStep)
        let far = PiPGeometry.initialFrame(size: size, in: visible, cascade: 500)
        XCTAssertTrue(visible.contains(far))
    }

    func testClampedMovesAFrameInsideTheBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(PiPGeometry.clamped(CGRect(x: 900, y: -50, width: 300, height: 200), in: bounds),
                       CGRect(x: 700, y: 0, width: 300, height: 200))
        XCTAssertEqual(PiPGeometry.clamped(CGRect(x: 10, y: 10, width: 300, height: 200), in: bounds),
                       CGRect(x: 10, y: 10, width: 300, height: 200))
    }

    func testResizedFrameKeepsTheCenterAndTheAspect() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frame = CGRect(x: 500, y: 300, width: 320, height: 180)
        let resized = PiPGeometry.resizedFrame(frame, toWidth: 480, aspect: 16.0 / 9.0, within: visible)
        XCTAssertEqual(resized, CGRect(x: 420, y: 255, width: 480, height: 270))
        XCTAssertEqual(CGPoint(x: resized.midX, y: resized.midY), CGPoint(x: frame.midX, y: frame.midY))
    }

    func testResizedFrameFollowsADisplayTheUserDraggedItTo() {
        let visible = CGRect(x: 1440, y: 900, width: 1920, height: 1055)
        let frame = CGRect(x: 2000, y: 1200, width: 320, height: 180)
        let resized = PiPGeometry.resizedFrame(frame, toWidth: 240, aspect: 16.0 / 9.0, within: visible)
        XCTAssertEqual(resized.size, CGSize(width: 240, height: 135))
        XCTAssertEqual(resized.origin, CGPoint(x: 2040, y: 1222.5))
    }

    func testResizedFrameStaysInsideTheDisplayWhenItGrowsPastAnEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = CGRect(x: 800, y: 600, width: 200, height: 200)
        let resized = PiPGeometry.resizedFrame(frame, toWidth: 400, aspect: 1, within: visible)
        XCTAssertEqual(resized, CGRect(x: 600, y: 400, width: 400, height: 400))
    }

    private let panel = CGSize(width: 320, height: 180)

    private func action(_ x: CGFloat, _ y: CGFloat, _ modifiers: NSEvent.ModifierFlags = []) -> PiPInteraction.Action {
        PiPInteraction.action(at: CGPoint(x: x, y: y), modifiers: modifiers, panelSize: panel)
    }

    func testTheTopBarDragsBetweenTheTopCornersEvenWithoutModifiers() {
        let corner = PiPInteraction.topCornerSize
        for x in [corner, 160, 320 - corner - 1] {
            XCTAssertEqual(action(x, 175), .drag)
            XCTAssertEqual(action(x, 180), .drag)
        }
        XCTAssertEqual(action(160, 180 - PiPInteraction.dragBarHeight + 1), .drag)
        XCTAssertEqual(action(2, 175 - corner), .drag)
    }

    func testTheControlsRowUnderTheBarIsControlsEvenWithOption() {
        let y = 180 - PiPInteraction.dragBarHeight - 10
        XCTAssertEqual(action(160, y), .controls)
        XCTAssertEqual(action(160, y, .option), .controls)
        XCTAssertEqual(action(PiPInteraction.edgeWidth, y), .controls)
        XCTAssertEqual(action(320 - PiPInteraction.edgeWidth - 1, y), .controls)
    }

    func testThePictureForwardsUnlessOptionIsHeld() {
        XCTAssertEqual(action(160, 60), .forward)
        XCTAssertEqual(action(160, 60, .shift), .forward)
        XCTAssertEqual(action(160, 60, .option), .drag)
        XCTAssertEqual(action(160, 60, [.option, .command]), .drag)
    }

    func testThereIsNoBorderRingDragJustInsideTheEdges() {
        let edge = PiPInteraction.edgeWidth
        XCTAssertEqual(action(edge, 60), .forward)
        XCTAssertEqual(action(320 - edge - 1, 60), .forward)
        XCTAssertEqual(action(160, edge), .forward)
        XCTAssertEqual(action(edge + 6, 60), .forward)
    }

    func testEachCornerResizesAndWinsOverEdgesAndOption() {
        let bottom = PiPInteraction.cornerSize - 1
        let top = PiPInteraction.topCornerSize - 1
        XCTAssertEqual(action(0, 0), .resize(.bottomLeft))
        XCTAssertEqual(action(bottom, bottom), .resize(.bottomLeft))
        XCTAssertEqual(action(320, 0), .resize(.bottomRight))
        XCTAssertEqual(action(320 - bottom, bottom, .option), .resize(.bottomRight))
        XCTAssertEqual(action(0, 180), .resize(.topLeft))
        XCTAssertEqual(action(top, 180 - top), .resize(.topLeft))
        XCTAssertEqual(action(320, 180), .resize(.topRight))
        XCTAssertEqual(action(320 - top, 180 - top, .option), .resize(.topRight))
    }

    func testTheCornerZonesStopWhereTheEdgesAndTheBarTakeOver() {
        XCTAssertEqual(action(PiPInteraction.cornerSize, 5), .resize(.bottom))
        XCTAssertEqual(action(5, PiPInteraction.cornerSize), .resize(.left))
        XCTAssertEqual(action(PiPInteraction.topCornerSize, 175), .drag)
        XCTAssertEqual(action(5, 180 - PiPInteraction.topCornerSize), .drag)
        XCTAssertEqual(action(5, 180 - PiPInteraction.topCornerSize - PiPInteraction.dragBarHeight), .resize(.left))
    }

    func testTheLeftRightAndBottomEdgesResizeButTheTopEdgeIsTheDragBar() {
        let edge = PiPInteraction.edgeWidth
        XCTAssertEqual(action(0, 90), .resize(.left))
        XCTAssertEqual(action(edge - 1, 90), .resize(.left))
        XCTAssertEqual(action(320, 90), .resize(.right))
        XCTAssertEqual(action(320 - edge + 1, 90), .resize(.right))
        XCTAssertEqual(action(160, 0), .resize(.bottom))
        XCTAssertEqual(action(160, edge - 1), .resize(.bottom))
        XCTAssertEqual(action(160, 90, .option), .drag)
        XCTAssertEqual(action(0, 90, .option), .resize(.left))
        XCTAssertEqual(action(160, 180), .drag)
    }

    func testTheEdgesBesideTheControlsRowStillResize() {
        let y = 180 - PiPInteraction.dragBarHeight - 10
        XCTAssertEqual(action(PiPInteraction.edgeWidth - 1, y), .resize(.left))
        XCTAssertEqual(action(320 - PiPInteraction.edgeWidth + 1, y), .resize(.right))
    }

    func testTheCornerZonesStayClearOfTheEndButtonsOfTheControlsRow() {
        let firstButtonFromTop = PiPInteraction.controlsRow.lowerBound + (PiPInteraction.controlsBarHeight - 22) / 2
        XCTAssertGreaterThanOrEqual(firstButtonFromTop, PiPInteraction.topCornerSize)
        XCTAssertGreaterThanOrEqual(180 - PiPInteraction.cornerSize, PiPInteraction.controlsRow.upperBound)
        XCTAssertEqual(action(PiPInteraction.edgeWidth + 2, 180 - firstButtonFromTop - 11), .controls)
    }

    func testPointsOutsideThePanelAreForwarded() {
        XCTAssertEqual(action(-3, 60, .option), .forward)
        XCTAssertEqual(action(160, 181, .option), .forward)
        XCTAssertEqual(action(321, 90), .forward)
    }

    func testEveryResizeAnchorDragsItsOwnCornerOrEdgeMiddle() {
        let frame = CGRect(x: 100, y: 200, width: 320, height: 180)
        XCTAssertEqual(PiPResizeAnchor.topLeft.point(on: frame), CGPoint(x: 100, y: 380))
        XCTAssertEqual(PiPResizeAnchor.topRight.point(on: frame), CGPoint(x: 420, y: 380))
        XCTAssertEqual(PiPResizeAnchor.bottomLeft.point(on: frame), CGPoint(x: 100, y: 200))
        XCTAssertEqual(PiPResizeAnchor.bottomRight.point(on: frame), CGPoint(x: 420, y: 200))
        XCTAssertEqual(PiPResizeAnchor.top.point(on: frame), CGPoint(x: 260, y: 380))
        XCTAssertEqual(PiPResizeAnchor.bottom.point(on: frame), CGPoint(x: 260, y: 200))
        XCTAssertEqual(PiPResizeAnchor.left.point(on: frame), CGPoint(x: 100, y: 290))
        XCTAssertEqual(PiPResizeAnchor.right.point(on: frame), CGPoint(x: 420, y: 290))
        XCTAssertEqual(PiPResizeAnchor.allCases.filter(\.isCorner).count, 4)
    }

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let start = CGRect(x: 500, y: 300, width: 320, height: 180)
    private let wide = 16.0 / 9.0

    private func resized(_ anchor: PiPResizeAnchor, to point: CGPoint, from frame: CGRect? = nil,
                         aspect: CGFloat? = nil, bounds: CGRect? = nil) -> CGRect {
        PiPGeometry.resized(frame: frame ?? start, anchor: anchor, to: point, aspect: aspect ?? wide, bounds: bounds ?? screen)
    }

    func testDraggingTheTopRightCornerKeepsTheBottomLeftFixed() {
        XCTAssertEqual(resized(.topRight, to: CGPoint(x: 980, y: 570)), CGRect(x: 500, y: 300, width: 480, height: 270))
        XCTAssertEqual(resized(.topRight, to: CGPoint(x: 660, y: 700)), CGRect(x: 500, y: 300, width: 711, height: 400))
    }

    func testDraggingTheTopLeftCornerKeepsTheBottomRightFixed() {
        let result = resized(.topLeft, to: CGPoint(x: 340, y: 480))
        XCTAssertEqual(result, CGRect(x: 340, y: 300, width: 480, height: 270))
        XCTAssertEqual(result.maxX, start.maxX)
        XCTAssertEqual(result.minY, start.minY)
    }

    func testDraggingTheBottomRightCornerKeepsTheTopLeftFixed() {
        let result = resized(.bottomRight, to: CGPoint(x: 980, y: 210))
        XCTAssertEqual(result, CGRect(x: 500, y: 210, width: 480, height: 270))
        XCTAssertEqual(result.minX, start.minX)
        XCTAssertEqual(result.maxY, start.maxY)
    }

    func testDraggingTheBottomLeftCornerKeepsTheTopRightFixed() {
        let result = resized(.bottomLeft, to: CGPoint(x: 340, y: 210))
        XCTAssertEqual(result, CGRect(x: 340, y: 210, width: 480, height: 270))
        XCTAssertEqual(result.maxX, start.maxX)
        XCTAssertEqual(result.maxY, start.maxY)
    }

    func testACornerDragFollowsWhicheverAxisTheCursorMovedFurther() {
        XCTAssertEqual(resized(.bottomRight, to: CGPoint(x: 830, y: 470)).width, 330)
        XCTAssertEqual(resized(.bottomRight, to: CGPoint(x: 700, y: 120)).width, 640)
    }

    func testDraggingTheRightEdgeKeepsTheLeftEdgeAndTheVerticalCenter() {
        let result = resized(.right, to: CGPoint(x: 980, y: 0))
        XCTAssertEqual(result, CGRect(x: 500, y: 255, width: 480, height: 270))
        XCTAssertEqual(result.midY, start.midY)
    }

    func testDraggingTheLeftEdgeKeepsTheRightEdgeAndTheVerticalCenter() {
        let result = resized(.left, to: CGPoint(x: 340, y: 0))
        XCTAssertEqual(result, CGRect(x: 340, y: 255, width: 480, height: 270))
        XCTAssertEqual(result.maxX, start.maxX)
    }

    func testDraggingTheBottomEdgeKeepsTheTopEdgeAndTheHorizontalCenter() {
        let result = resized(.bottom, to: CGPoint(x: 0, y: 210))
        XCTAssertEqual(result, CGRect(x: 420, y: 210, width: 480, height: 270))
        XCTAssertEqual(result.maxY, start.maxY)
        XCTAssertEqual(result.midX, start.midX)
    }

    func testDraggingTheTopEdgeKeepsTheBottomEdgeAndTheHorizontalCenter() {
        let result = resized(.top, to: CGPoint(x: 0, y: 570))
        XCTAssertEqual(result, CGRect(x: 420, y: 300, width: 480, height: 270))
        XCTAssertEqual(result.minY, start.minY)
        XCTAssertEqual(result.midX, start.midX)
    }

    func testAResizeNeverGoesBelowTheMinimumWidth() {
        for anchor in PiPResizeAnchor.allCases {
            let result = resized(anchor, to: anchor.point(on: start).applying(CGAffineTransform(translationX: anchor.growsLeft ? 900 : -900,
                                                                                                  y: anchor.growsDown ? 900 : -900)))
            XCTAssertEqual(result.width, PiPGeometry.minimumWidth, "\(anchor)")
            XCTAssertEqual(result.height, (PiPGeometry.minimumWidth / wide).rounded(), "\(anchor)")
        }
    }

    func testTheMinimumWidthCanBeRaised() {
        let result = PiPGeometry.resized(frame: start, anchor: .bottomRight, to: CGPoint(x: 0, y: 480), aspect: wide, minWidth: 200, bounds: screen)
        XCTAssertEqual(result.width, 200)
    }

    func testAResizeStopsAtTheDisplayEdgeAndKeepsTheOppositeSide() {
        let right = resized(.bottomRight, to: CGPoint(x: 5000, y: -5000))
        XCTAssertEqual(right.minX, start.minX)
        XCTAssertEqual(right.maxY, start.maxY)
        XCTAssertTrue(screen.contains(right))
        XCTAssertEqual(right.width / right.height, wide, accuracy: 0.02)
        let left = resized(.topLeft, to: CGPoint(x: -5000, y: 5000))
        XCTAssertEqual(left.maxX, start.maxX)
        XCTAssertEqual(left.minY, start.minY)
        XCTAssertTrue(screen.contains(left))
    }

    func testAnEdgeResizeStaysInsideTheDisplayOnTheOtherAxis() {
        let result = resized(.right, to: CGPoint(x: 1400, y: 0), from: CGRect(x: 500, y: 690, width: 320, height: 180))
        XCTAssertEqual(result, CGRect(x: 500, y: 685, width: 338, height: 190))
        XCTAssertTrue(screen.contains(result))
    }

    func testResizingWorksOnADisplayAboveTheMainOne() {
        let above = CGRect(x: -200, y: 875, width: 1920, height: 1055)
        let frame = CGRect(x: 100, y: 1500, width: 320, height: 180)
        let result = resized(.topRight, to: CGPoint(x: 580, y: 1770), from: frame, bounds: above)
        XCTAssertEqual(result, CGRect(x: 100, y: 1500, width: 480, height: 270))
        let capped = resized(.topRight, to: CGPoint(x: 5000, y: 5000), from: frame, bounds: above)
        XCTAssertEqual(capped.origin, frame.origin)
        XCTAssertTrue(above.contains(capped))
    }

    func testResizingWorksOnADisplayWithNegativeCoordinates() {
        let below = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let frame = CGRect(x: -800, y: -600, width: 320, height: 180)
        let result = resized(.bottomLeft, to: CGPoint(x: -960, y: -690), from: frame, bounds: below)
        XCTAssertEqual(result, CGRect(x: -960, y: -690, width: 480, height: 270))
        let capped = resized(.bottomLeft, to: CGPoint(x: -9000, y: -9000), from: frame, bounds: below)
        XCTAssertEqual(capped.maxX, frame.maxX)
        XCTAssertEqual(capped.maxY, frame.maxY)
        XCTAssertTrue(below.contains(capped))
    }

    func testResizingKeepsATallAspectLocked() {
        let result = resized(.bottomRight, to: CGPoint(x: 720, y: 100), from: CGRect(x: 500, y: 300, width: 200, height: 400), aspect: 0.5)
        XCTAssertEqual(result.width / result.height, 0.5, accuracy: 0.01)
        XCTAssertEqual(result.minX, 500)
        XCTAssertEqual(result.maxY, 700)
    }

    func testTheControlsRowStartsRightBelowTheDragBar() {
        XCTAssertEqual(PiPInteraction.controlsRow.lowerBound, PiPInteraction.dragBarHeight)
        XCTAssertEqual(PiPInteraction.controlsRow.upperBound, PiPInteraction.dragBarHeight + PiPInteraction.controlsBarHeight)
    }

    func testPanelCenterMapsToTheWindowCenter() {
        let point = PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 160, y: 90), panelSize: CGSize(width: 320, height: 180),
                                            windowFrame: CGRect(x: 100, y: 200, width: 1280, height: 720))
        XCTAssertEqual(point, CGPoint(x: 740, y: 560))
    }

    func testPanelTopLeftMapsToTheWindowTopLeftBecauseThePanelYGrowsUp() {
        let frame = CGRect(x: 100, y: 200, width: 1280, height: 720)
        let panel = CGSize(width: 320, height: 180)
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 0, y: 180), panelSize: panel, windowFrame: frame),
                       CGPoint(x: 100, y: 200))
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 320, y: 0), panelSize: panel, windowFrame: frame),
                       CGPoint(x: 1380, y: 920))
    }

    func testMappingWorksForAWindowOnADisplayAboveTheMainOne() {
        let above = CGRect(x: -200, y: -900, width: 800, height: 600)
        let point = PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 100, y: 150), panelSize: CGSize(width: 400, height: 300),
                                            windowFrame: above)
        XCTAssertEqual(point, CGPoint(x: 0, y: -600))
    }

    func testMappingUsesPointsSoARetinaWindowMapsLikeANormalOne() {
        let panel = CGSize(width: 320, height: 200)
        let frame = CGRect(x: 0, y: -1080, width: 1600, height: 1000)
        let retinaCapture = PiPGeometry.captureSize(windowSize: frame.size, scale: 2)
        XCTAssertEqual(retinaCapture, CGSize(width: 3200, height: 2000))
        XCTAssertEqual(PiPGeometry.aspect(of: retinaCapture), PiPGeometry.aspect(of: frame.size))
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 80, y: 150), panelSize: panel, windowFrame: frame),
                       CGPoint(x: 400, y: -830))
    }

    func testMappingFollowsAResizedPanel() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let small = PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 80, y: 60), panelSize: CGSize(width: 160, height: 120),
                                            windowFrame: frame)
        let large = PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 240, y: 180), panelSize: CGSize(width: 480, height: 360),
                                            windowFrame: frame)
        XCTAssertEqual(small, large)
    }

    func testMappingNeedsAPanelWithSize() {
        XCTAssertNil(PiPGeometry.globalPoint(forPanelPoint: .zero, panelSize: .zero, windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    func testOrdinaryWindowCanGetAPiP() {
        XCTAssertNil(PiPEligibility.block(isMinimized: false, isFullScreen: false, pid: 10, ownPID: 99))
    }

    func testMinimizedFullScreenAndOwnWindowsCannot() {
        XCTAssertEqual(PiPEligibility.block(isMinimized: true, isFullScreen: false, pid: 10, ownPID: 99), .minimized)
        XCTAssertEqual(PiPEligibility.block(isMinimized: false, isFullScreen: true, pid: 10, ownPID: 99), .fullScreen)
        XCTAssertEqual(PiPEligibility.block(isMinimized: false, isFullScreen: false, pid: 99, ownPID: 99), .ownApp)
    }

    func testOwnAppWinsOverTheOtherReasons() {
        XCTAssertEqual(PiPEligibility.block(isMinimized: true, isFullScreen: true, pid: 99, ownPID: 99), .ownApp)
    }

    func testEveryBlockHasAReasonForTheTooltip() {
        for block in [PiPEligibility.Block.ownApp, .minimized, .fullScreen] {
            XCTAssertFalse(block.reason.isEmpty)
        }
    }

    private func decide(hidden: Bool = false, minimized: Bool = false, blank: TimeInterval = 0) -> PiPSourceState {
        PiPSourceState.decide(appHidden: hidden, minimized: minimized, secondsOfBlankFrames: blank)
    }

    func testAVisibleWindowIsLive() {
        XCTAssertEqual(decide(), .live)
    }

    func testAHiddenAppIsUnavailableAsHiddenEvenWhenMinimizedAndBlank() {
        XCTAssertEqual(decide(hidden: true), .unavailable(.hidden))
        XCTAssertEqual(decide(hidden: true, minimized: true, blank: 5), .unavailable(.hidden))
    }

    func testAMinimizedWindowIsUnavailableAsMinimizedEvenWhenBlank() {
        XCTAssertEqual(decide(minimized: true), .unavailable(.minimized))
        XCTAssertEqual(decide(minimized: true, blank: 5), .unavailable(.minimized))
    }

    func testAWindowOnAnotherSpaceStaysLiveUntilItsFramesStayBlank() {
        XCTAssertEqual(decide(blank: 0), .live)
        XCTAssertEqual(decide(blank: PiPSourceState.blankTolerance), .live)
    }

    func testBlankFramesCountOnlyAfterTheTolerance() {
        XCTAssertEqual(decide(blank: PiPSourceState.blankTolerance), .live)
        XCTAssertEqual(decide(blank: PiPSourceState.blankTolerance + 0.1), .unavailable(.notVisible))
    }

    func testEveryReasonHasATitleAndASymbol() {
        XCTAssertEqual(PiPSourceState.Reason.hidden.title, "Window hidden")
        XCTAssertEqual(PiPSourceState.Reason.minimized.title, "Window minimized")
        XCTAssertEqual(PiPSourceState.Reason.notVisible.title, "Window not visible")
        for reason in [PiPSourceState.Reason.hidden, .minimized, .notVisible] {
            XCTAssertNotNil(NSImage(systemSymbolName: reason.symbol, accessibilityDescription: nil))
        }
    }

    func testOnlyACompleteFrameOfTheCaptureWidthIsValid() {
        let size = CGSize(width: 1600, height: 900)
        XCTAssertTrue(PiPSourceState.isValidFrame(status: .complete, surfaceSize: size, expectedWidth: 1600))
        XCTAssertTrue(PiPSourceState.isValidFrame(status: .complete, surfaceSize: size, expectedWidth: 1601))
        for status in [SCFrameStatus.idle, .blank, .suspended, .stopped, .started] {
            XCTAssertFalse(PiPSourceState.isValidFrame(status: status, surfaceSize: size, expectedWidth: 1600))
        }
    }

    func testAFrameWithNoSizeOrTheWrongWidthIsNotValid() {
        XCTAssertFalse(PiPSourceState.isValidFrame(status: .complete, surfaceSize: .zero, expectedWidth: 0))
        XCTAssertFalse(PiPSourceState.isValidFrame(status: .complete, surfaceSize: CGSize(width: 1600, height: 0),
                                                   expectedWidth: 1600))
        XCTAssertFalse(PiPSourceState.isValidFrame(status: .complete, surfaceSize: CGSize(width: 800, height: 450),
                                                   expectedWidth: 1600))
    }
}
