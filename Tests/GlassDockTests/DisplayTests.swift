import XCTest
@testable import GlassDock

final class DisplayTests: XCTestCase {
    func testAllDisplaysGetADock() {
        XCTAssertEqual(DockDisplayMode.allDisplays.displayIDs(among: [7, 3, 9]), [7, 3, 9])
    }

    func testMainDisplayModeKeepsOnlyTheFirstDisplay() {
        XCTAssertEqual(DockDisplayMode.mainDisplay.displayIDs(among: [7, 3, 9]), [7])
    }

    func testNoDisplaysMeansNoDock() {
        XCTAssertEqual(DockDisplayMode.allDisplays.displayIDs(among: []), [])
        XCTAssertEqual(DockDisplayMode.mainDisplay.displayIDs(among: []), [])
    }

    func testNotchMetricsUseTheSafeAreaAndShiftToTheNotchCenter() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let metrics = IslandMetrics(frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
                                    safeAreaTop: 32, topLeftWidth: 660, topRightWidth: 652)
        XCTAssertTrue(metrics.hasNotch)
        XCTAssertEqual(metrics.notchWidth, 200)
        XCTAssertEqual(metrics.notchHeight, 32)
        XCTAssertEqual(metrics.centerX, 760)
        XCTAssertEqual(metrics.screenTop, 982)
    }

    func testScreenWithoutNotchGetsAPillFromTheMenuBarHeight() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let metrics = IslandMetrics(frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
                                    safeAreaTop: 0, topLeftWidth: nil, topRightWidth: nil)
        XCTAssertFalse(metrics.hasNotch)
        XCTAssertEqual(metrics.notchWidth, 150)
        XCTAssertEqual(metrics.notchHeight, 25)
        XCTAssertEqual(metrics.centerX, 1280)
    }

    func testExternalDisplayMetricsFollowItsPositionInTheDesktop() {
        let frame = CGRect(x: 1512, y: 200, width: 1920, height: 1080)
        let metrics = IslandMetrics(frame: frame, visibleFrame: CGRect(x: 1512, y: 200, width: 1920, height: 1080),
                                    safeAreaTop: 0, topLeftWidth: nil, topRightWidth: nil)
        XCTAssertEqual(metrics.centerX, 2472)
        XCTAssertEqual(metrics.screenTop, 1280)
        XCTAssertEqual(metrics.notchHeight, 24)
    }

    func testMenuBarHeightBelowTheMinimumIsRaisedToIt() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let metrics = IslandMetrics(frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 790),
                                    safeAreaTop: 0, topLeftWidth: nil, topRightWidth: nil)
        XCTAssertEqual(metrics.notchHeight, 24)
    }
}

final class BrightnessTargetTests: XCTestCase {
    func testTheDisplayUnderTheCursorWinsWhenItCanBeDimmed() {
        XCTAssertEqual(BrightnessTarget.display(underCursor: 4, adjustable: [1, 4], builtIn: 1), 4)
    }

    func testAnExternalMonitorWithoutBrightnessControlFallsBackToTheBuiltInPanel() {
        XCTAssertEqual(BrightnessTarget.display(underCursor: 4, adjustable: [1], builtIn: 1), 1)
        XCTAssertEqual(BrightnessTarget.display(underCursor: nil, adjustable: [1], builtIn: 1), 1)
    }

    func testNothingAdjustableLeavesTheKeyToMacOS() {
        XCTAssertNil(BrightnessTarget.display(underCursor: 4, adjustable: [], builtIn: nil))
        XCTAssertNil(BrightnessTarget.display(underCursor: 4, adjustable: [2], builtIn: nil))
        XCTAssertNil(BrightnessTarget.display(underCursor: 4, adjustable: [2], builtIn: 1))
    }
}

final class IslandWithoutNotchModeTests: XCTestCase {
    func testNotchedDisplaysIgnoreTheSetting() {
        for mode in IslandWithoutNotchMode.allCases {
            XCTAssertTrue(mode.showsIsland(hasNotch: true))
            XCTAssertTrue(mode.showsIdlePill(hasNotch: true))
        }
    }

    func testAlwaysShownKeepsThePillOnDisplaysWithoutANotch() {
        XCTAssertTrue(IslandWithoutNotchMode.alwaysShown.showsIsland(hasNotch: false))
        XCTAssertTrue(IslandWithoutNotchMode.alwaysShown.showsIdlePill(hasNotch: false))
    }

    func testShowOnHoverKeepsTheWindowButHidesTheIdlePill() {
        XCTAssertTrue(IslandWithoutNotchMode.onHover.showsIsland(hasNotch: false))
        XCTAssertFalse(IslandWithoutNotchMode.onHover.showsIdlePill(hasNotch: false))
    }

    func testOffRemovesTheIslandFromDisplaysWithoutANotch() {
        XCTAssertFalse(IslandWithoutNotchMode.off.showsIsland(hasNotch: false))
        XCTAssertFalse(IslandWithoutNotchMode.off.showsIdlePill(hasNotch: false))
    }
}
