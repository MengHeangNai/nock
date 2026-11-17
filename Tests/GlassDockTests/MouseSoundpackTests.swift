import AVFoundation
import XCTest
@testable import GlassDock

final class MouseSoundpackTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testPackLoadsEachEventFileWhateverItsCase() throws {
        let pack = try makePack("full", tones: ["click.wav": 0.1, "Release.CAF": 0.05, "right.wav": 0.2, "middle.wav": 0.15,
                                                "scroll.wav": 0.02])

        XCTAssertNil(pack.unavailableReason)
        XCTAssertEqual(pack.id, "mouse:full")
        XCTAssertEqual(pack.name, "full")
        XCTAssertEqual(try frames(pack.sounds[.click]), 4_800, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.release]), 2_400, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.right]), 9_600, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.middle]), 7_200, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.scroll]), 960, accuracy: 64)
        XCTAssertTrue(pack.sounds[.rightRelease] === pack.sounds[.release])
        XCTAssertTrue(pack.sounds[.middleRelease] === pack.sounds[.release])
        XCTAssertEqual(pack.sounds[.click]?.format, KeyboardSoundpack.format)
    }

    func testMissingOrBrokenOptionalFilesFallBackToTheClick() throws {
        let pack = try makePack("click-only", tones: ["click.wav": 0.1],
                                bytes: ["click.txt": Data("not audio".utf8), "right.ogg": Data("not audio".utf8)])

        XCTAssertNil(pack.unavailableReason)
        for sound in MouseSound.allCases {
            XCTAssertNotNil(pack.sounds[sound], "\(sound)")
            XCTAssertTrue(pack.sounds[sound] === pack.sounds[.click], "\(sound)")
        }
    }

    func testPacksWithoutAUsableClickAreUnavailable() throws {
        let noClick = try makePack("no-click", tones: ["release.wav": 0.1])
        let badClick = try makePack("bad-click", tones: ["release.wav": 0.1], bytes: ["click.ogg": Data("not audio".utf8)])

        XCTAssertEqual(noClick.unavailableReason, MouseSoundpack.missingClick)
        XCTAssertEqual(badClick.unavailableReason, KeyboardSoundpack.unsupportedOGG)
        XCTAssertTrue(noClick.sounds.isEmpty && badClick.sounds.isEmpty)
        XCTAssertNil(badClick.sounds[.release])
    }

    func testMechvibesSinglePackMapsButtonsAndTheirReleaseTimings() throws {
        let pack = try makePack("v2-single", tones: ["sound.wav": 1], config: [
            "name": "Test Mouse", "config_version": "2", "definition_method": "single", "audio_file": "sound.wav",
            "definitions": [
                "MouseLeft": ["timing": [[0, 100], [100, 150]]],
                "MouseRight": ["timing": [[200, 400]]],
                "MouseMiddle": ["timing": [[400, 500], [500, 700]]],
                "MouseWheelUp": ["timing": [[700, 720]]],
            ],
        ])

        XCTAssertNil(pack.unavailableReason)
        XCTAssertEqual(pack.id, "mouse:v2-single")
        XCTAssertEqual(pack.name, "Test Mouse")
        XCTAssertEqual(try frames(pack.sounds[.click]), 4_800, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.release]), 2_400, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.right]), 9_600, accuracy: 64)
        XCTAssertNil(pack.sounds[.rightRelease])
        XCTAssertEqual(try frames(pack.sounds[.middle]), 4_800, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.middleRelease]), 9_600, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.scroll]), 960, accuracy: 64)
        XCTAssertEqual(pack.sounds[.click]?.format, KeyboardSoundpack.format)
    }

    func testMechvibesPackWithoutReleaseTimingsReleasesSilentlyAndFallsBackToMouseLeft() throws {
        let pack = try makePack("v2-press-only", tones: ["concatenated_audio.wav": 0.7], config: [
            "name": "Press Only", "config_version": "2", "definition_method": "single", "audio_file": "concatenated_audio.wav",
            "definitions": [
                "MouseLeft": ["timing": [[0, 167.959]]],
                "MouseRight": ["timing": [[167.959, 335.918]]],
            ],
        ])

        XCTAssertNil(pack.unavailableReason)
        XCTAssertEqual(try frames(pack.sounds[.click]), 8_062, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.right]), 8_062, accuracy: 64)
        XCTAssertFalse(pack.sounds[.right] === pack.sounds[.click])
        XCTAssertTrue(pack.sounds[.middle] === pack.sounds[.click])
        XCTAssertTrue(pack.sounds[.scroll] === pack.sounds[.click])
        XCTAssertNil(pack.sounds[.release])
        XCTAssertNil(pack.sounds[.rightRelease])
        XCTAssertNil(pack.sounds[.middleRelease])
    }

    func testMechvibesMultiPackUsesEachButtonsFileAndThePackFileWhole() throws {
        try writeTone(to: root.appendingPathComponent("outside.wav"), seconds: 0.1)
        let pack = try makePack("v2-multi", tones: ["left.wav": 0.1, "main.wav": 0.3], config: [
            "config_version": 2, "definition_method": "multi", "audio_file": "main.wav",
            "defs": [
                "MouseLeft": ["audio_file": "left.wav"],
                "MouseRight": [String: Any](),
                "MouseMiddle": ["audio_file": "../outside.wav"],
                "Wheel": ["audio_file": "main.wav", "timing": [[0, 20], [20, 40]]],
            ],
        ])

        XCTAssertNil(pack.unavailableReason)
        XCTAssertEqual(pack.name, "v2-multi")
        XCTAssertEqual(try frames(pack.sounds[.click]), 4_800, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.right]), 14_400, accuracy: 64)
        XCTAssertEqual(try frames(pack.sounds[.scroll]), 960, accuracy: 64)
        XCTAssertTrue(pack.sounds[.middle] === pack.sounds[.click])
        XCTAssertNil(pack.sounds[.release])
        XCTAssertNil(pack.sounds[.rightRelease])
    }

    func testBrokenMechvibesPacksAreUnavailableWithTheirReason() throws {
        let noLeft = try makePack("no-left", tones: ["sound.wav": 0.5], config: [
            "name": "No Left", "audio_file": "sound.wav", "definitions": ["MouseRight": ["timing": [[0, 100]]]],
        ])
        let leftOutsideFile = try makePack("left-outside", tones: ["sound.wav": 0.1], config: [
            "audio_file": "sound.wav",
            "definitions": ["MouseLeft": ["timing": [[500, 600]]], "MouseRight": ["timing": [[0, 50]]]],
        ])
        let missingFile = try makePack("missing-file", tones: [:], config: [
            "audio_file": "gone.wav", "definitions": ["MouseLeft": ["timing": [[0, 100]]]],
        ])
        let keyboardPack = try makePack("keyboard", tones: ["sound.wav": 0.5], config: [
            "key_define_type": "single", "sound": "sound.wav", "defines": ["30": [0, 100]],
        ])
        let brokenConfig = try makePack("broken-config", tones: ["click.wav": 0.1],
                                        bytes: [KeyboardSoundpack.configFileName: Data("{".utf8)])

        XCTAssertEqual(noLeft.name, "No Left")
        XCTAssertEqual(noLeft.unavailableReason, MouseSoundpack.missingMouseLeft)
        XCTAssertEqual(leftOutsideFile.unavailableReason, MouseSoundpack.unplayableMouseLeft)
        XCTAssertEqual(missingFile.unavailableReason, "Sound file is missing or outside the pack.")
        XCTAssertEqual(keyboardPack.unavailableReason, KeyboardSoundpack.unrecognisedFormat)
        XCTAssertEqual(brokenConfig.unavailableReason, "Missing or unreadable config.json.")
        for pack in [noLeft, leftOutsideFile, missingFile, keyboardPack, brokenConfig] {
            XCTAssertTrue(pack.sounds.isEmpty, pack.id)
        }
    }

    func testScanListsOnlyFoldersInNameOrder() throws {
        try makePack("Pack 10", tones: ["click.wav": 0.05])
        try makePack("Pack 2", tones: ["click.wav": 0.05])
        try writeTone(to: root.appendingPathComponent("click.wav"), seconds: 0.05)

        XCTAssertEqual(MouseSoundpack.scan(root).map(\.id), ["mouse:Pack 2", "mouse:Pack 10"])
    }

    private func frames(_ buffer: AVAudioPCMBuffer?) throws -> Double {
        Double(try XCTUnwrap(buffer).frameLength)
    }

    @discardableResult
    private func makePack(_ folderName: String, tones: [String: Double], bytes: [String: Data] = [:],
                          config: [String: Any]? = nil) throws -> MouseSoundpack {
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, seconds) in tones {
            try writeTone(to: folder.appendingPathComponent(name), seconds: seconds)
        }
        for (name, data) in bytes {
            try data.write(to: folder.appendingPathComponent(name))
        }
        if let config {
            try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent(KeyboardSoundpack.configFileName))
        }
        return MouseSoundpack.load(from: folder)
    }
}
