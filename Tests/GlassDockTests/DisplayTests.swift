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

    func testOnlyGlassDocksVendorAndProductIdentifyTheHiddenDisplay() {
        XCTAssertTrue(HiddenDisplayIdentity.matches(vendorID: HiddenDisplayIdentity.vendorID, productID: HiddenDisplayIdentity.productID))
        XCTAssertFalse(HiddenDisplayIdentity.matches(vendorID: HiddenDisplayIdentity.vendorID, productID: 0x0610))
        XCTAssertFalse(HiddenDisplayIdentity.matches(vendorID: 0x0610, productID: HiddenDisplayIdentity.productID))
        XCTAssertFalse(HiddenDisplayIdentity.matches(vendorID: 0, productID: 0))
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

final class IslandPetShapeTests: XCTestCase {
    private func metrics(hasNotch: Bool) -> IslandMetrics {
        hasNotch
            ? IslandMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
                            safeAreaTop: 32, topLeftWidth: 660, topRightWidth: 652)
            : IslandMetrics(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
                            safeAreaTop: 0, topLeftWidth: nil, topRightWidth: nil)
    }

    func testThePetWingIsAboutHalfAsWideAsAMusicWing() {
        let notched = metrics(hasNotch: true)
        XCTAssertEqual(notched.petWingWidth, 30)
        XCTAssertLessThan(notched.petWingWidth, notched.wingWidth * 0.6)
        XCTAssertGreaterThanOrEqual(notched.petWingWidth, notched.notchHeight * 0.78)
    }

    func testTheNotchlessPetWingFitsThePetToo() {
        let pill = metrics(hasNotch: false)
        XCTAssertEqual(pill.petWingWidth, 33)
        XCTAssertGreaterThanOrEqual(pill.petWingWidth, pill.notchHeight * 0.78)
    }

    func testTheShapeGrowsByAPetWingOnEachSideSoItStaysCenteredOnTheNotch() {
        for hasNotch in [true, false] {
            let metrics = metrics(hasNotch: hasNotch)
            XCTAssertEqual(metrics.petSize.width, metrics.notchWidth + metrics.petWingWidth * 2)
            XCTAssertEqual(metrics.petSize.height, metrics.notchHeight)
        }
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

final class IslandFullScreenTests: XCTestCase {
    private let builtIn = "0A1B2C3D-0000-4000-8000-000000000001"
    private let external = "0A1B2C3D-0000-4000-8000-000000000002"

    private func display(_ identifier: String, spaceType: Int) -> [String: Any] {
        ["Display Identifier": identifier, "Current Space": ["type": spaceType, "ManagedSpaceID": 42]]
    }

    func testADisplayShowingAFullScreenSpaceIsFullScreen() {
        let spaces = [display(builtIn, spaceType: 4), display(external, spaceType: 0)]
        XCTAssertTrue(IslandSpace.isFullScreen(displayUUID: builtIn, in: spaces))
    }

    func testOtherDisplaysAreUnaffected() {
        let spaces = [display(builtIn, spaceType: 4), display(external, spaceType: 0)]
        XCTAssertFalse(IslandSpace.isFullScreen(displayUUID: external, in: spaces))
    }

    func testADesktopSpaceIsNotFullScreen() {
        XCTAssertFalse(IslandSpace.isFullScreen(displayUUID: builtIn, in: [display(builtIn, spaceType: 0)]))
    }

    func testTheDisplayIdentifierMatchesRegardlessOfCase() {
        XCTAssertTrue(IslandSpace.isFullScreen(displayUUID: builtIn.lowercased(), in: [display(builtIn, spaceType: 4)]))
    }

    func testWithoutSeparateSpacesAFullScreenSpaceCoversEveryDisplay() {
        let spaces = [display("Main", spaceType: 4)]
        XCTAssertTrue(IslandSpace.isFullScreen(displayUUID: builtIn, in: spaces))
        XCTAssertTrue(IslandSpace.isFullScreen(displayUUID: external, in: spaces))
    }

    func testMissingOrMalformedSpacesAreNeverFullScreen() {
        XCTAssertFalse(IslandSpace.isFullScreen(displayUUID: builtIn, in: []))
        XCTAssertFalse(IslandSpace.isFullScreen(displayUUID: builtIn, in: [["Display Identifier": builtIn]]))
        XCTAssertFalse(IslandSpace.isFullScreen(displayUUID: builtIn, in: [["Current Space": ["type": 4]]]))
    }
}
