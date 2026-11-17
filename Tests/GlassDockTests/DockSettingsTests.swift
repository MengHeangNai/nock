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

    func testMouseClickSoundsMigrateToMatchKeyboard() throws {
        let suite = UUID().uuidString
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        store.set(true, forKey: "keyboardSoundMouseClicks")

        XCTAssertEqual(DockSettings.mouseSoundID(in: store), MouseSoundProfile.matchKeyboardID)
        XCTAssertEqual(store.string(forKey: "mouseSound"), MouseSoundProfile.matchKeyboardID)
        XCTAssertNil(store.object(forKey: "keyboardSoundMouseClicks"))
    }

    func testMouseSoundsStartOffAndKeepTheSavedChoice() throws {
        let suite = UUID().uuidString
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DockSettings.mouseSoundID(in: store), MouseSoundProfile.offID)
        store.set(MouseSoundProfile.crisp.rawValue, forKey: "mouseSound")
        store.set(true, forKey: "keyboardSoundMouseClicks")
        XCTAssertEqual(DockSettings.mouseSoundID(in: store), MouseSoundProfile.crisp.rawValue)
    }
}
