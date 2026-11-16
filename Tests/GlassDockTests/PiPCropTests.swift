import CoreGraphics
import XCTest
@testable import GlassDock

final class PiPCropTests: XCTestCase {
    private let window = CGSize(width: 1000, height: 500)
    private let unit = CGSize(width: 1, height: 1)

    private func crop(_ selection: CGRect, in view: CGSize? = nil, window: CGSize? = nil) -> PiPCrop? {
        PiPCrop(selection: selection, in: view ?? unit, windowSize: window ?? self.window)
    }

    func testASelectionBecomesAFractionOfTheWindow() {
        let result = crop(CGRect(x: 100, y: 50, width: 200, height: 100), in: CGSize(width: 400, height: 200))
        XCTAssertEqual(result?.rect, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    func testASelectionDraggedBackwardsIsStandardized() {
        let result = crop(CGRect(x: 0.5, y: 0.5, width: -0.25, height: -0.25))
        XCTAssertEqual(result?.rect, CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
    }

    func testASelectionPastTheEdgesIsMovedInside() {
        let result = crop(CGRect(x: 0.8, y: -0.1, width: 0.4, height: 0.3))
        XCTAssertEqual(result?.rect, CGRect(x: 0.6, y: 0, width: 0.4, height: 0.3))
    }

    func testASelectionLargerThanTheWindowIsTheWholeWindow() {
        XCTAssertEqual(crop(CGRect(x: -1, y: -1, width: 5, height: 5))?.rect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testATinySelectionGrowsToTheMinimumSourceSize() {
        let result = crop(CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001))
        XCTAssertEqual(result?.sourceRect(in: window).width ?? 0, PiPCrop.minimumSourceSize, accuracy: 0.0001)
        XCTAssertEqual(result?.sourceRect(in: window).height ?? 0, PiPCrop.minimumSourceSize, accuracy: 0.0001)
    }

    func testTheMinimumSizeStaysInsideTheWindowAtItsEdge() {
        let result = crop(CGRect(x: 0.999, y: 0.999, width: 0, height: 0))
        XCTAssertEqual(result?.rect.maxX ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(result?.rect.maxY ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(result?.sourceRect(in: window).width ?? 0, PiPCrop.minimumSourceSize, accuracy: 0.0001)
    }

    func testAWindowSmallerThanTheMinimumIsCroppedToItsWholeSize() {
        XCTAssertEqual(crop(CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1), window: CGSize(width: 30, height: 30))?.rect,
                       CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testNoCropWithoutASizedPictureOrWindow() {
        XCTAssertNil(crop(CGRect(x: 0, y: 0, width: 1, height: 1), in: .zero))
        XCTAssertNil(crop(CGRect(x: 0, y: 0, width: 1, height: 1), window: CGSize(width: 0, height: 500)))
    }

    func testTheSourceRectIsInWindowPointsFromTheTopLeft() {
        let result = crop(CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4))
        let source = result?.sourceRect(in: window)
        XCTAssertEqual(source?.origin.x ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(source?.origin.y ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(source?.width ?? 0, 500, accuracy: 0.0001)
        XCTAssertEqual(source?.height ?? 0, 200, accuracy: 0.0001)
    }

    func testTheSourceRectFollowsAResizedWindow() {
        let result = crop(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertEqual(result?.sourceRect(in: CGSize(width: 2000, height: 800)), CGRect(x: 1000, y: 400, width: 1000, height: 400))
    }

    func testTheCropAspectIsTheAspectOfTheCroppedPoints() {
        let result = crop(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(result?.aspect(in: window) ?? 0, 1, accuracy: 0.0001)
    }

    func testTheCaptureSizeIsTheCroppedPointsTimesTheBackingScale() {
        let result = crop(CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4))
        XCTAssertEqual(result?.captureSize(in: window, scale: 2), CGSize(width: 1000, height: 400))
        XCTAssertEqual(result?.captureSize(in: window, scale: 1), CGSize(width: 500, height: 200))
    }

    func testTheFrameIsTheCroppedPartOfTheWindowFrame() {
        let result = crop(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertEqual(result?.frame(in: CGRect(x: 100, y: -900, width: 1000, height: 500)),
                       CGRect(x: 600, y: -650, width: 500, height: 250))
    }

    func testOnlyAFrameOfTheCroppedWidthIsValid() {
        let result = crop(CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let expected = Int(result?.captureSize(in: window, scale: 2).width ?? 0)
        XCTAssertEqual(expected, 1000)
        XCTAssertTrue(PiPSourceState.isValidFrame(status: .complete, surfaceSize: CGSize(width: 1000, height: 500), expectedWidth: expected))
        XCTAssertFalse(PiPSourceState.isValidFrame(status: .complete, surfaceSize: CGSize(width: 2000, height: 1000), expectedWidth: expected))
    }

    func testAPanelPointInACropNotAtTheOriginMapsInsideTheRealWindow() {
        let result = crop(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let frame = CGRect(x: 100, y: 200, width: 1000, height: 500)
        let panel = CGSize(width: 250, height: 125)
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 0, y: 125), panelSize: panel, windowFrame: frame, crop: result),
                       CGPoint(x: 600, y: 450))
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 250, y: 0), panelSize: panel, windowFrame: frame, crop: result),
                       CGPoint(x: 1100, y: 700))
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 125, y: 62.5), panelSize: panel, windowFrame: frame, crop: result),
                       CGPoint(x: 850, y: 575))
    }

    func testACropMappingDoesNotDependOnTheRetinaScale() {
        let result = crop(CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5))
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 500)
        XCTAssertEqual(result?.captureSize(in: frame.size, scale: 2), CGSize(width: 1000, height: 500))
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 100, y: 50), panelSize: CGSize(width: 200, height: 100),
                                               windowFrame: frame, crop: result),
                       CGPoint(x: 500, y: 125))
    }

    func testACropMappingWorksForAWindowOnADisplayAboveTheMainOne() {
        let result = crop(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let above = CGRect(x: -200, y: -900, width: 800, height: 600)
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 100, y: 150), panelSize: CGSize(width: 400, height: 300),
                                               windowFrame: above, crop: result),
                       CGPoint(x: 300, y: -450))
    }

    func testACropMappingFollowsAResizedWindowAndPanel() {
        let result = crop(CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        let small = PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 50, y: 50), panelSize: CGSize(width: 100, height: 100),
                                            windowFrame: CGRect(x: 0, y: 0, width: 400, height: 400), crop: result)
        let large = PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 100, y: 100), panelSize: CGSize(width: 200, height: 200),
                                            windowFrame: CGRect(x: 0, y: 0, width: 400, height: 400), crop: result)
        XCTAssertEqual(small, large)
        XCTAssertEqual(small, CGPoint(x: 300, y: 100))
    }

    func testNoCropMapsTheWholeWindowLikeBefore() {
        XCTAssertEqual(PiPGeometry.globalPoint(forPanelPoint: CGPoint(x: 160, y: 90), panelSize: CGSize(width: 320, height: 180),
                                               windowFrame: CGRect(x: 100, y: 200, width: 1280, height: 720), crop: nil),
                       CGPoint(x: 740, y: 560))
    }

    func testMinimumSizeScalesToThePicture() {
        let size = PiPCrop.minimumSize(in: CGSize(width: 500, height: 250), windowSize: window)
        XCTAssertEqual(size.width, 24, accuracy: 0.0001)
        XCTAssertEqual(size.height, 24, accuracy: 0.0001)
    }

    func testDrawingGrowsAwayFromTheStartAndStaysInsideThePicture() {
        let bounds = CGSize(width: 400, height: 200)
        let minimum = CGSize(width: 20, height: 20)
        XCTAssertEqual(PiPCrop.drawnRect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 50, y: 40), within: bounds, minimumSize: minimum),
                       CGRect(x: 50, y: 40, width: 50, height: 60))
        XCTAssertEqual(PiPCrop.drawnRect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 500, y: 300), within: bounds, minimumSize: minimum),
                       CGRect(x: 100, y: 100, width: 300, height: 100))
        XCTAssertEqual(PiPCrop.drawnRect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 90), within: bounds, minimumSize: minimum),
                       CGRect(x: 100, y: 80, width: 20, height: 20))
    }

    func testEveryResizeHandleSitsOnItsCornerOrEdge() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 60)
        XCTAssertEqual(PiPCropHandle.resizeHandles.count, 8)
        XCTAssertEqual(PiPCropHandle.topLeft.anchor(in: rect), CGPoint(x: 10, y: 20))
        XCTAssertEqual(PiPCropHandle.top.anchor(in: rect), CGPoint(x: 60, y: 20))
        XCTAssertEqual(PiPCropHandle.topRight.anchor(in: rect), CGPoint(x: 110, y: 20))
        XCTAssertEqual(PiPCropHandle.right.anchor(in: rect), CGPoint(x: 110, y: 50))
        XCTAssertEqual(PiPCropHandle.bottomRight.anchor(in: rect), CGPoint(x: 110, y: 80))
        XCTAssertEqual(PiPCropHandle.bottom.anchor(in: rect), CGPoint(x: 60, y: 80))
        XCTAssertEqual(PiPCropHandle.bottomLeft.anchor(in: rect), CGPoint(x: 10, y: 80))
        XCTAssertEqual(PiPCropHandle.left.anchor(in: rect), CGPoint(x: 10, y: 50))
    }

    func testAPressFindsTheHandleUnderIt() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        func handle(_ x: CGFloat, _ y: CGFloat) -> PiPCropHandle? {
            PiPCropHandle.handle(at: CGPoint(x: x, y: y), in: rect, tolerance: 8)
        }
        XCTAssertEqual(handle(102, 98), .topLeft)
        XCTAssertEqual(handle(200, 104), .top)
        XCTAssertEqual(handle(296, 96), .topRight)
        XCTAssertEqual(handle(304, 150), .right)
        XCTAssertEqual(handle(300, 200), .bottomRight)
        XCTAssertEqual(handle(200, 205), .bottom)
        XCTAssertEqual(handle(95, 205), .bottomLeft)
        XCTAssertEqual(handle(96, 150), .left)
        XCTAssertEqual(handle(200, 150), .move)
        XCTAssertNil(handle(50, 150))
        XCTAssertNil(handle(200, 250))
    }

    func testDraggingACornerMovesTwoEdgesAndKeepsTheMinimumSize() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let bounds = CGSize(width: 400, height: 300)
        let minimum = CGSize(width: 30, height: 30)
        XCTAssertEqual(PiPCropHandle.topLeft.dragged(rect, by: CGSize(width: 20, height: -40), within: bounds, minimumSize: minimum),
                       CGRect(x: 120, y: 60, width: 180, height: 140))
        XCTAssertEqual(PiPCropHandle.topLeft.dragged(rect, by: CGSize(width: 500, height: 500), within: bounds, minimumSize: minimum),
                       CGRect(x: 270, y: 170, width: 30, height: 30))
        XCTAssertEqual(PiPCropHandle.bottomRight.dragged(rect, by: CGSize(width: 500, height: 500), within: bounds, minimumSize: minimum),
                       CGRect(x: 100, y: 100, width: 300, height: 200))
        XCTAssertEqual(PiPCropHandle.bottomRight.dragged(rect, by: CGSize(width: -500, height: -500), within: bounds, minimumSize: minimum),
                       CGRect(x: 100, y: 100, width: 30, height: 30))
    }

    func testDraggingAnEdgeMovesOnlyThatEdge() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let bounds = CGSize(width: 400, height: 300)
        let minimum = CGSize(width: 30, height: 30)
        XCTAssertEqual(PiPCropHandle.right.dragged(rect, by: CGSize(width: 50, height: 70), within: bounds, minimumSize: minimum),
                       CGRect(x: 100, y: 100, width: 250, height: 100))
        XCTAssertEqual(PiPCropHandle.top.dragged(rect, by: CGSize(width: 50, height: -150), within: bounds, minimumSize: minimum),
                       CGRect(x: 100, y: 0, width: 200, height: 200))
        XCTAssertEqual(PiPCropHandle.left.dragged(rect, by: CGSize(width: -150, height: 0), within: bounds, minimumSize: minimum),
                       CGRect(x: 0, y: 100, width: 300, height: 100))
        XCTAssertEqual(PiPCropHandle.bottom.dragged(rect, by: CGSize(width: 0, height: 10), within: bounds, minimumSize: minimum),
                       CGRect(x: 100, y: 100, width: 200, height: 110))
    }

    func testMovingKeepsTheSizeAndStaysInsideThePicture() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let bounds = CGSize(width: 400, height: 300)
        let minimum = CGSize(width: 30, height: 30)
        XCTAssertEqual(PiPCropHandle.move.dragged(rect, by: CGSize(width: 40, height: -20), within: bounds, minimumSize: minimum),
                       CGRect(x: 140, y: 80, width: 200, height: 100))
        XCTAssertEqual(PiPCropHandle.move.dragged(rect, by: CGSize(width: 500, height: 500), within: bounds, minimumSize: minimum),
                       CGRect(x: 200, y: 200, width: 200, height: 100))
        XCTAssertEqual(PiPCropHandle.move.dragged(rect, by: CGSize(width: -500, height: -500), within: bounds, minimumSize: minimum),
                       CGRect(x: 0, y: 0, width: 200, height: 100))
    }
}
