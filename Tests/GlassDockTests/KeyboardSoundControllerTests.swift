import AppKit
import XCTest
@testable import GlassDock

final class KeyboardSoundRecipeTests: XCTestCase {
    private let sampleRate = 48_000.0

    func testEverySoundIsShortAudibleAndNeverClips() {
        for profile in KeyboardSoundProfile.allCases {
            for sound in KeyboardSound.allCases {
                let samples = profile.recipe(for: sound).samples(sampleRate: sampleRate)
                let peak = samples.map(abs).max() ?? 0
                XCTAssertFalse(samples.isEmpty, "\(profile) \(sound)")
                XCTAssertLessThan(Double(samples.count) / sampleRate, 0.15, "\(profile) \(sound)")
                XCTAssertLessThan(peak, 1, "\(profile) \(sound)")
                XCTAssertGreaterThan(peak, 0.1, "\(profile) \(sound)")
                XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.001, "\(profile) \(sound) ends silent")
            }
        }
        for profile in MouseSoundProfile.allCases {
            for sound in MouseSound.allCases {
                let samples = profile.recipe(for: sound).samples(sampleRate: sampleRate)
                let peak = samples.map(abs).max() ?? 0
                XCTAssertLessThan(Double(samples.count) / sampleRate, 0.15, "\(profile) \(sound)")
                XCTAssertLessThan(peak, 1, "\(profile) \(sound)")
                XCTAssertGreaterThan(peak, 0.1, "\(profile) \(sound)")
                XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.001, "\(profile) \(sound) ends silent")
            }
        }
    }

    func testKeyReleaseIsQuieterThanKeyPress() {
        for profile in KeyboardSoundProfile.allCases {
            let press = profile.recipe(for: .down).samples(sampleRate: sampleRate).map(abs).max() ?? 0
            let release = profile.recipe(for: .up).samples(sampleRate: sampleRate).map(abs).max() ?? 0
            XCTAssertLessThan(release, press, "\(profile)")
        }
        for profile in MouseSoundProfile.allCases {
            let click = profile.recipe(for: .click).samples(sampleRate: sampleRate).map(abs).max() ?? 0
            let release = profile.recipe(for: .release).samples(sampleRate: sampleRate).map(abs).max() ?? 0
            let scroll = profile.recipe(for: .scroll).samples(sampleRate: sampleRate).map(abs).max() ?? 0
            XCTAssertLessThan(release, click, "\(profile)")
            XCTAssertLessThan(scroll, release, "\(profile)")
        }
    }

    func testEveryProfileSurvivesASaveAndLoad() {
        for profile in KeyboardSoundProfile.allCases {
            XCTAssertEqual(KeyboardSoundProfile(rawValue: profile.rawValue), profile)
        }
        XCTAssertNil(KeyboardSoundProfile(rawValue: "linear"))
        for profile in MouseSoundProfile.allCases {
            XCTAssertEqual(MouseSoundProfile(rawValue: profile.rawValue), profile)
            XCTAssertNotEqual(profile.rawValue, MouseSoundProfile.offID)
            XCTAssertNotEqual(profile.rawValue, MouseSoundProfile.matchKeyboardID)
        }
    }

    func testScrollTicksAreRateLimitedAndSkipMomentum() throws {
        let scroll = try scrollEvent(momentum: false)
        let momentum = try scrollEvent(momentum: true)
        let tick = KeyboardSoundController.scrollTickSeconds

        XCTAssertTrue(KeyboardSoundController.isScrollTick(scroll, lastTick: 0))
        XCTAssertTrue(KeyboardSoundController.isScrollTick(scroll, lastTick: scroll.timestamp - tick * 1.2))
        XCTAssertFalse(KeyboardSoundController.isScrollTick(scroll, lastTick: scroll.timestamp - tick / 2))
        XCTAssertFalse(KeyboardSoundController.isScrollTick(momentum, lastTick: 0))
    }

    private func scrollEvent(momentum: Bool) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 6, wheel2: 0, wheel3: 0))
        event.timestamp = 5_000_000_000
        if momentum {
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(CGMomentumScrollPhase.continuous.rawValue))
        }
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }
}
