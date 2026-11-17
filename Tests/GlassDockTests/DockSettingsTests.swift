import XCTest
@testable import GlassDock

final class DockSettingsTests: XCTestCase {
    func testCurveDefaultsToOneAndClampsToRange() {
        XCTAssertEqual(DockSettings.islandCurve(nil), 1)
        XCTAssertEqual(DockSettings.islandCurve(0.4), 0.4)
        XCTAssertEqual(DockSettings.islandCurve(-1), 0)
        XCTAssertEqual(DockSettings.islandCurve(5), 2)
    }

    func testSavedCurvesStayInRange() {
        let settings = DockSettings.shared
        let saved = (settings.islandShoulderCurve, settings.islandCornerCurve)
        defer { (settings.islandShoulderCurve, settings.islandCornerCurve) = saved }

        settings.islandShoulderCurve = 5
        settings.islandCornerCurve = -1
        XCTAssertEqual(settings.islandShoulderCurve, 2)
        XCTAssertEqual(settings.islandCornerCurve, 0)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "islandShoulderCurve"), 2)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "islandCornerCurve"), 0)
    }
}
