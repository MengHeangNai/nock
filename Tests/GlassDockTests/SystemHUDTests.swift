import XCTest
@testable import GlassDock

final class SystemHUDTests: XCTestCase {
    private func volume(_ value: Float, muted: Bool = false) -> HUDReading {
        HUDReading(kind: .volume, value: value, isMuted: muted)
    }

    func testPercentRoundsTheValue() {
        XCTAssertEqual(volume(0.5).percent, 50)
        XCTAssertEqual(volume(0.126).percent, 13)
        XCTAssertEqual(volume(1).percent, 100)
    }

    func testOutOfRangeValueIsClamped() {
        XCTAssertEqual(volume(1.4).level, 1)
        XCTAssertEqual(volume(-0.2).level, 0)
        XCTAssertEqual(HUDReading(kind: .brightness, value: 2).percent, 100)
    }

    func testMutedVolumeShowsEmptyWithTheSlashedSpeaker() {
        let muted = volume(0.8, muted: true)
        XCTAssertEqual(muted.level, 0)
        XCTAssertEqual(muted.percent, 0)
        XCTAssertEqual(muted.symbol, "speaker.slash.fill")
    }

    func testEachKindHasItsOwnSymbolLabelAndFillValue() {
        XCTAssertEqual(volume(0.25).symbol, "speaker.wave.3.fill")
        XCTAssertEqual(volume(0.25).label, "Volume")
        XCTAssertEqual(volume(0.25).symbolValue, 0.25)
        XCTAssertEqual(HUDReading(kind: .brightness, value: 0.5).symbol, "sun.max.fill")
        XCTAssertEqual(HUDReading(kind: .brightness, value: 0.2).symbol, "sun.min.fill")
        XCTAssertEqual(HUDReading(kind: .brightness, value: 0.5).label, "Brightness")
        XCTAssertEqual(HUDReading(kind: .keyboardBacklight, value: 0.5).symbol, "light.max")
        XCTAssertEqual(HUDReading(kind: .keyboardBacklight, value: 0).symbol, "light.min")
        XCTAssertEqual(HUDReading(kind: .keyboardBacklight, value: 0.5).label, "Keyboard Brightness")
    }

    func testAttachingToADeviceNeverShowsTheHUD() {
        var tracker = VolumeHUDTracker()
        tracker.rebase(to: volume(0.5))
        XCTAssertFalse(tracker.observe(volume(0.5)))
    }

    func testAChangedVolumeShowsTheHUD() {
        var tracker = VolumeHUDTracker()
        tracker.rebase(to: volume(0.5))
        XCTAssertTrue(tracker.observe(volume(0.56)))
        XCTAssertFalse(tracker.observe(volume(0.56)))
        XCTAssertTrue(tracker.observe(volume(0.62)))
    }

    func testMutingAndUnmutingShowTheHUD() {
        var tracker = VolumeHUDTracker()
        tracker.rebase(to: volume(0.5))
        XCTAssertTrue(tracker.observe(volume(0.5, muted: true)))
        XCTAssertTrue(tracker.observe(volume(0.5)))
    }

    func testSwitchingOutputDevicesRebasesWithoutShowing() {
        var tracker = VolumeHUDTracker()
        tracker.rebase(to: volume(0.5))
        tracker.rebase(to: volume(0.9))
        XCTAssertFalse(tracker.observe(volume(0.9)))
    }

    func testReadingWithoutABaselineIsAdoptedSilently() {
        var tracker = VolumeHUDTracker()
        tracker.rebase(to: nil)
        XCTAssertFalse(tracker.observe(volume(0.3)))
        XCTAssertTrue(tracker.observe(volume(0.4)))
    }

    func testAChangeWeMadeIsNotShownTwice() {
        var tracker = VolumeHUDTracker()
        tracker.rebase(to: volume(0.5))
        tracker.rebase(to: volume(0.5625))
        XCTAssertFalse(tracker.observe(volume(0.5625)))
    }
}

final class HUDAccessTests: XCTestCase {
    private func resolve(setting: Bool = true, island: Bool = true, trusted: Bool = true, tap: Bool = true) -> (HUDAccess, tapStarts: Int) {
        var starts = 0
        let access = HUDAccess.resolve(replacesSystemHUD: setting, isIslandShown: island, isTrusted: trusted) {
            starts += 1
            return tap
        }
        return (access, starts)
    }

    func testSettingOffWinsOverEverythingElse() {
        XCTAssertEqual(resolve(setting: false, island: false, trusted: false).0, .settingOff)
        XCTAssertEqual(resolve(setting: false).0, .settingOff)
    }

    func testIslandOffIsOnlyReportedWhenTheSettingIsOn() {
        XCTAssertEqual(resolve(island: false).0, .islandOff)
        XCTAssertEqual(resolve(island: false, trusted: false).0, .islandOff)
    }

    func testMissingAccessibilityNeedsAccessibility() {
        XCTAssertEqual(resolve(trusted: false).0, .needsAccessibility)
    }

    func testTheTapIsNeverStartedBeforeAllConditionsHold() {
        XCTAssertEqual(resolve(setting: false).tapStarts, 0)
        XCTAssertEqual(resolve(island: false).tapStarts, 0)
        XCTAssertEqual(resolve(trusted: false).tapStarts, 0)
    }

    func testTrustedWithBothOnStartsTheTapAndReplaces() {
        let result = resolve()
        XCTAssertEqual(result.0, .replacing)
        XCTAssertEqual(result.tapStarts, 1)
    }

    func testARefusedTapIsReported() {
        XCTAssertEqual(resolve(tap: false).0, .tapRefused)
    }

    func testGrantingAccessibilityLaterMovesFromNeedsAccessibilityToReplacing() {
        XCTAssertEqual(resolve(trusted: false).0, .needsAccessibility)
        XCTAssertEqual(resolve(trusted: true).0, .replacing)
    }

    func testOnlyTheSettingAndIslandOffStatesAreDisabled() {
        XCTAssertFalse(HUDAccess.settingOff.isEnabled)
        XCTAssertFalse(HUDAccess.islandOff.isEnabled)
        XCTAssertTrue(HUDAccess.needsAccessibility.isEnabled)
        XCTAssertTrue(HUDAccess.tapRefused.isEnabled)
        XCTAssertTrue(HUDAccess.replacing.isEnabled)
    }
}

final class MediaKeyPressTests: XCTestCase {
    private func data1(key: Int, state: Int, isRepeat: Bool = false) -> Int {
        (key << 16) | (state << 8) | (isRepeat ? 1 : 0)
    }

    func testDecodesAKeyPress() {
        let press = MediaKeyPress(subtype: 8, data1: data1(key: 0, state: 0xA), modifiers: [])
        XCTAssertEqual(press?.key, .soundUp)
        XCTAssertEqual(press?.isDown, true)
        XCTAssertEqual(press?.isRepeat, false)
    }

    func testDecodesARelease() {
        let press = MediaKeyPress(subtype: 8, data1: data1(key: 1, state: 0xB), modifiers: [])
        XCTAssertEqual(press?.key, .soundDown)
        XCTAssertEqual(press?.isDown, false)
    }

    func testDecodesAKeyRepeat() {
        XCTAssertEqual(MediaKeyPress(subtype: 8, data1: data1(key: 3, state: 0xA, isRepeat: true), modifiers: [])?.isRepeat, true)
    }

    func testDecodesEveryHandledKey() {
        let keys: [Int: MediaKey] = [0: .soundUp, 1: .soundDown, 7: .mute, 2: .brightnessUp, 3: .brightnessDown,
                                     21: .illuminationUp, 22: .illuminationDown, 23: .illuminationToggle]
        for (code, key) in keys {
            XCTAssertEqual(MediaKeyPress(subtype: 8, data1: data1(key: code, state: 0xA), modifiers: [])?.key, key)
        }
    }

    func testIgnoresOtherKeysAndEvents() {
        XCTAssertNil(MediaKeyPress(subtype: 8, data1: data1(key: 16, state: 0xA), modifiers: []))
        XCTAssertNil(MediaKeyPress(subtype: 7, data1: data1(key: 0, state: 0xA), modifiers: []))
        XCTAssertNil(MediaKeyPress(subtype: 8, data1: data1(key: 0, state: 0x5), modifiers: []))
    }

    func testShiftOptionTakesTheFineStep() {
        let down = data1(key: 0, state: 0xA)
        XCTAssertTrue(MediaKeyPress(subtype: 8, data1: down, modifiers: [.shift, .option])!.isFineStep)
        XCTAssertFalse(MediaKeyPress(subtype: 8, data1: down, modifiers: [.shift])!.isFineStep)
        XCTAssertFalse(MediaKeyPress(subtype: 8, data1: down, modifiers: [])!.isFineStep)
    }

    func testSystemShortcutsAreLeftToMacOS() {
        let down = data1(key: 0, state: 0xA)
        XCTAssertTrue(MediaKeyPress(subtype: 8, data1: down, modifiers: [.option])!.isLeftToSystem)
        XCTAssertTrue(MediaKeyPress(subtype: 8, data1: down, modifiers: [.command])!.isLeftToSystem)
        XCTAssertTrue(MediaKeyPress(subtype: 8, data1: down, modifiers: [.control])!.isLeftToSystem)
        XCTAssertFalse(MediaKeyPress(subtype: 8, data1: down, modifiers: [.shift, .option])!.isLeftToSystem)
        XCTAssertFalse(MediaKeyPress(subtype: 8, data1: down, modifiers: [.shift])!.isLeftToSystem)
        XCTAssertFalse(MediaKeyPress(subtype: 8, data1: down, modifiers: [])!.isLeftToSystem)
    }

    func testKeysMapToActions() {
        XCTAssertEqual(MediaKey.soundUp.action, .step(.volume, .up))
        XCTAssertEqual(MediaKey.soundDown.action, .step(.volume, .down))
        XCTAssertEqual(MediaKey.mute.action, .toggleMute)
        XCTAssertEqual(MediaKey.brightnessUp.action, .step(.brightness, .up))
        XCTAssertEqual(MediaKey.brightnessDown.action, .step(.brightness, .down))
        XCTAssertEqual(MediaKey.illuminationUp.action, .step(.keyboardBacklight, .up))
        XCTAssertEqual(MediaKey.illuminationDown.action, .step(.keyboardBacklight, .down))
        XCTAssertEqual(MediaKey.illuminationToggle.action, .toggleBacklight)
    }

    func testKeysBelongToTheirKind() {
        XCTAssertEqual(MediaKey.mute.kind, .volume)
        XCTAssertEqual(MediaKey.brightnessDown.kind, .brightness)
        XCTAssertEqual(MediaKey.illuminationToggle.kind, .keyboardBacklight)
    }
}

final class HUDStepTests: XCTestCase {
    func testStandardStepMovesOneSixteenth() {
        XCTAssertEqual(HUDStep.next(from: 0.5, direction: .up, steps: HUDStep.standard), 0.5625)
        XCTAssertEqual(HUDStep.next(from: 0.5, direction: .down, steps: HUDStep.standard), 0.4375)
    }

    func testFineStepMovesOneSixtyFourth() {
        XCTAssertEqual(HUDStep.next(from: 0.5, direction: .up, steps: HUDStep.fine), 33.0 / 64)
        XCTAssertEqual(HUDStep.next(from: 0.5, direction: .down, steps: HUDStep.fine), 31.0 / 64)
    }

    func testOffGridValuesSnapToTheNextStep() {
        XCTAssertEqual(HUDStep.next(from: 0.53, direction: .up, steps: HUDStep.standard), 0.5625)
        XCTAssertEqual(HUDStep.next(from: 0.53, direction: .down, steps: HUDStep.standard), 0.5)
    }

    func testStepsStayWithinTheRange() {
        XCTAssertEqual(HUDStep.next(from: 1, direction: .up, steps: HUDStep.standard), 1)
        XCTAssertEqual(HUDStep.next(from: 0, direction: .down, steps: HUDStep.standard), 0)
        XCTAssertEqual(HUDStep.next(from: 1.3, direction: .up, steps: HUDStep.standard), 1)
        XCTAssertEqual(HUDStep.next(from: -0.3, direction: .down, steps: HUDStep.standard), 0)
        XCTAssertEqual(HUDStep.next(from: 0.98, direction: .up, steps: HUDStep.standard), 1)
    }

    func testSixteenPressesCoverTheWholeRange() {
        var value: Float = 0
        for _ in 0..<16 { value = HUDStep.next(from: value, direction: .up, steps: HUDStep.standard) }
        XCTAssertEqual(value, 1)
        for _ in 0..<16 { value = HUDStep.next(from: value, direction: .down, steps: HUDStep.standard) }
        XCTAssertEqual(value, 0)
    }

    func testBacklightToggleSwitchesOffAndRestores() {
        XCTAssertEqual(HUDStep.toggledBacklight(from: 0.75, previous: 0.75), 0)
        XCTAssertEqual(HUDStep.toggledBacklight(from: 0, previous: 0.75), 0.75)
        XCTAssertEqual(HUDStep.toggledBacklight(from: 0, previous: 0), 0.5)
    }
}
