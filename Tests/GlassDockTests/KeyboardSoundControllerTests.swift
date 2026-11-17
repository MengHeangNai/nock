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
    }

    func testKeyReleaseIsQuieterThanKeyPress() {
        for profile in KeyboardSoundProfile.allCases {
            let press = profile.recipe(for: .down).samples(sampleRate: sampleRate).map(abs).max() ?? 0
            let release = profile.recipe(for: .up).samples(sampleRate: sampleRate).map(abs).max() ?? 0
            XCTAssertLessThan(release, press, "\(profile)")
        }
    }

    func testEveryProfileSurvivesASaveAndLoad() {
        for profile in KeyboardSoundProfile.allCases {
            XCTAssertEqual(KeyboardSoundProfile(rawValue: profile.rawValue), profile)
        }
        XCTAssertNil(KeyboardSoundProfile(rawValue: "linear"))
    }
}
