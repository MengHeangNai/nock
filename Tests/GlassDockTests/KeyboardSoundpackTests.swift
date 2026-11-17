import AVFoundation
import Carbon.HIToolbox
import XCTest
@testable import GlassDock

final class KeyboardSoundpackTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testSinglePackSlicesTheSoundFileAndCutsSlicesAtTheEnd() throws {
        let pack = try makePack("single", files: ["sound.wav": 0.5], config: [
            "name": "Test Single", "key_define_type": "single", "sound": "sound.wav",
            "defines": ["30": [0, 100], "57": [100, 200], "28": [400, 500], "14": [1e300, 100], "15": [-50, 100]],
        ])

        XCTAssertNil(pack.unavailableReason)
        XCTAssertEqual(pack.name, "Test Single")
        XCTAssertEqual(pack.id, "pack:single")
        XCTAssertEqual(try frames(pack.keySounds[kVK_ANSI_A]?.down), 4_800, accuracy: 64)
        XCTAssertEqual(try frames(pack.keySounds[kVK_Space]?.down), 9_600, accuracy: 64)
        XCTAssertEqual(try frames(pack.keySounds[kVK_Return]?.down), 4_800, accuracy: 64)
        XCTAssertNil(pack.keySounds[kVK_Delete])
        XCTAssertNil(pack.keySounds[kVK_Tab])
        XCTAssertNil(pack.keySounds[kVK_ANSI_A]?.up)
        XCTAssertEqual(pack.keySounds[kVK_ANSI_A]?.down.format, KeyboardSoundpack.format)
        XCTAssertTrue(pack.sound(forKeyCode: kVK_ANSI_A)?.down === pack.keySounds[kVK_ANSI_A]?.down)
    }

    func testMultiPackLoadsEachFileAndRejectsPathsOutsideThePack() throws {
        try writeTone(to: root.appendingPathComponent("outside.wav"), seconds: 0.1)
        let pack = try makePack("multi", files: ["a.wav": 0.1, "space.wav": 0.2], config: [
            "name": "Test Multi", "key_define_type": "multi",
            "defines": ["30": "a.wav", "57": "space.wav", "28": "../outside.wav", "1": NSNull()],
        ])

        XCTAssertNil(pack.unavailableReason)
        XCTAssertEqual(try frames(pack.keySounds[kVK_ANSI_A]?.down), 4_800, accuracy: 64)
        XCTAssertEqual(try frames(pack.keySounds[kVK_Space]?.down), 9_600, accuracy: 64)
        XCTAssertNil(pack.keySounds[kVK_Return])
        XCTAssertNil(pack.keySounds[kVK_Escape])
        XCTAssertNotNil(pack.sound(forKeyCode: kVK_Return), "keys without their own sound fall back to another one")
        XCTAssertNotNil(pack.sound(forKeyCode: nil))
    }

    func testV2SinglePackSlicesDownAndUpSoundsFromStartAndEnd() throws {
        let pack = try makePack("v2-single", files: ["sound.wav": 1], config: [
            "name": "Test V2", "config_version": "2", "definition_method": "single", "audio_file": "sound.wav",
            "definitions": [
                "KeyA": ["timing": [[0, 100], [150, 200]]],
                "Space": ["timing": [[200, 400]]],
                "Enter": ["timing": [[500, 400]]],
                "KeyB": ["timing": [[-10, 50]]],
                "Digit1": ["timing": [[900, 5_000]]],
                "Tab": ["timing": [[0, 10], [10, 20], [20, 30]]],
                "Escape": ["timing": [[1e300, 1e301]]],
            ],
        ])

        XCTAssertNil(pack.unavailableReason)
        XCTAssertEqual(pack.name, "Test V2")
        XCTAssertEqual(try frames(pack.keySounds[kVK_ANSI_A]?.down), 4_800, accuracy: 64)
        XCTAssertEqual(try frames(pack.keySounds[kVK_ANSI_A]?.up), 2_400, accuracy: 64)
        XCTAssertEqual(try frames(pack.keySounds[kVK_Space]?.down), 9_600, accuracy: 64)
        XCTAssertNil(pack.keySounds[kVK_Space]?.up)
        XCTAssertEqual(try frames(pack.keySounds[kVK_ANSI_1]?.down), 4_800, accuracy: 64)
        XCTAssertNil(pack.keySounds[kVK_Return])
        XCTAssertNil(pack.keySounds[kVK_ANSI_B])
        XCTAssertNil(pack.keySounds[kVK_Tab])
        XCTAssertNil(pack.keySounds[kVK_Escape])
        XCTAssertTrue(pack.sound(forKeyCode: kVK_ANSI_A)?.up === pack.keySounds[kVK_ANSI_A]?.up)
    }

    func testV2MultiPackUsesEachKeysFileAndFallsBackToThePackFile() throws {
        try writeTone(to: root.appendingPathComponent("outside.wav"), seconds: 0.1)
        let pack = try makePack("v2-multi", files: ["a.wav": 0.1, "space.wav": 0.2, "main.wav": 0.3], config: [
            "config_version": 2, "definition_method": "multi", "audio_file": "main.wav",
            "defs": [
                "KeyA": ["audio_file": "a.wav"],
                "Space": ["audio_file": "space.wav", "timing": [[0, 50], [50, 1_000]]],
                "Enter": [String: Any](),
                "KeyB": ["audio_file": "../outside.wav"],
            ],
        ])

        XCTAssertNil(pack.unavailableReason)
        XCTAssertEqual(try frames(pack.keySounds[kVK_ANSI_A]?.down), 4_800, accuracy: 64)
        XCTAssertEqual(try frames(pack.keySounds[kVK_Space]?.down), 2_400, accuracy: 64)
        XCTAssertEqual(try frames(pack.keySounds[kVK_Space]?.up), 7_200, accuracy: 64)
        XCTAssertEqual(try frames(pack.keySounds[kVK_Return]?.down), 14_400, accuracy: 64)
        XCTAssertNil(pack.keySounds[kVK_ANSI_B])
    }

    func testBrokenPacksAreListedAsUnavailable() throws {
        let missingConfig = root.appendingPathComponent("no-config", isDirectory: true)
        try FileManager.default.createDirectory(at: missingConfig, withIntermediateDirectories: true)
        try makePack("absolute", files: [:], config: [
            "key_define_type": "single", "sound": "/System/Library/Sounds/Tink.aiff", "defines": ["30": [0, 50]],
        ])
        let garbage = try makePack("garbage", files: [:], config: [
            "key_define_type": "multi", "defines": ["30": "key.ogg"],
        ], extraFiles: ["key.ogg": Data("not audio".utf8)])
        let unknown = try makePack("unknown", files: ["sound.wav": 0.1], config: [
            "name": "Unknown", "sound": "sound.wav", "keys": ["KeyA": [0, 50]],
        ])

        let packs = KeyboardSoundpack.scan(root)

        XCTAssertEqual(packs.map(\.id), ["pack:absolute", "pack:garbage", "pack:no-config", "pack:unknown"])
        XCTAssertTrue(packs.allSatisfy { !$0.isAvailable && $0.keySounds.isEmpty })
        XCTAssertEqual(garbage.unavailableReason, KeyboardSoundpack.unsupportedOGG)
        XCTAssertEqual(unknown.unavailableReason, KeyboardSoundpack.unrecognisedFormat)
    }

    func testMacKeyCodesMapToMechvibesKeyNames() {
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_ANSI_A]?.scancode, 30)
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_ANSI_A]?.code, "KeyA")
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_Space]?.scancode, 57)
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_Space]?.code, "Space")
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_Return]?.scancode, 28)
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_Return]?.code, "Enter")
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_Escape]?.scancode, 1)
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_Command]?.scancode, 3675)
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_Command]?.code, "MetaLeft")
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_Delete]?.code, "Backspace")
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_ForwardDelete]?.code, "Delete")
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_ANSI_Keypad7]?.scancode, 71)
        XCTAssertEqual(KeyboardSoundpack.keyNames[kVK_ANSI_Keypad7]?.code, "Numpad7")
        XCTAssertEqual(Set(KeyboardSoundpack.keyNames.values.map(\.code)).count, KeyboardSoundpack.keyNames.count)
        XCTAssertEqual(Set(KeyboardSoundpack.keyNames.values.map(\.scancode)).count, KeyboardSoundpack.keyNames.count)
    }

    private func frames(_ buffer: AVAudioPCMBuffer?) throws -> Double {
        Double(try XCTUnwrap(buffer).frameLength)
    }

    @discardableResult
    private func makePack(_ folderName: String, files: [String: Double], config: [String: Any],
                          extraFiles: [String: Data] = [:]) throws -> KeyboardSoundpack {
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, seconds) in files {
            try writeTone(to: folder.appendingPathComponent(name), seconds: seconds)
        }
        for (name, data) in extraFiles {
            try data.write(to: folder.appendingPathComponent(name))
        }
        try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent("config.json"))
        return KeyboardSoundpack.load(from: folder)
    }

    private func writeTone(to url: URL, seconds: Double) throws {
        let rate = 44_100.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            for index in 0..<Int(frames) {
                buffer.floatChannelData?[channel][index] = Float(sin(2 * .pi * 440 * Double(index) / rate) * 0.5)
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        try file.write(from: buffer)
    }
}
