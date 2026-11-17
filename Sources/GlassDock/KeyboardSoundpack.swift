import AVFoundation
import Carbon.HIToolbox

struct KeyboardSoundpack: Identifiable {
    struct KeySound {
        let down: AVAudioPCMBuffer
        let up: AVAudioPCMBuffer?
    }

    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GlassDock/Soundpacks", isDirectory: true)
    static let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    static let configFileName = "config.json"
    static let maxConfigBytes = 1_000_000
    static let maxAudioFileBytes = 50_000_000
    static let maxDefines = 512
    static let maxKeySoundSeconds = 1.0
    static let unsupportedOGG = "OGG audio not supported on this Mac. Convert it to WAV or MP3."
    static let unrecognisedFormat = "Unrecognised soundpack format."

    static let keyNames: [Int: (scancode: Int, code: String)] = [
        kVK_Escape: (1, "Escape"), kVK_ANSI_1: (2, "Digit1"), kVK_ANSI_2: (3, "Digit2"), kVK_ANSI_3: (4, "Digit3"),
        kVK_ANSI_4: (5, "Digit4"), kVK_ANSI_5: (6, "Digit5"), kVK_ANSI_6: (7, "Digit6"), kVK_ANSI_7: (8, "Digit7"),
        kVK_ANSI_8: (9, "Digit8"), kVK_ANSI_9: (10, "Digit9"), kVK_ANSI_0: (11, "Digit0"),
        kVK_ANSI_Minus: (12, "Minus"), kVK_ANSI_Equal: (13, "Equal"), kVK_Delete: (14, "Backspace"), kVK_Tab: (15, "Tab"),
        kVK_ANSI_Q: (16, "KeyQ"), kVK_ANSI_W: (17, "KeyW"), kVK_ANSI_E: (18, "KeyE"), kVK_ANSI_R: (19, "KeyR"),
        kVK_ANSI_T: (20, "KeyT"), kVK_ANSI_Y: (21, "KeyY"), kVK_ANSI_U: (22, "KeyU"), kVK_ANSI_I: (23, "KeyI"),
        kVK_ANSI_O: (24, "KeyO"), kVK_ANSI_P: (25, "KeyP"), kVK_ANSI_LeftBracket: (26, "BracketLeft"),
        kVK_ANSI_RightBracket: (27, "BracketRight"), kVK_Return: (28, "Enter"), kVK_Control: (29, "ControlLeft"),
        kVK_ANSI_A: (30, "KeyA"), kVK_ANSI_S: (31, "KeyS"), kVK_ANSI_D: (32, "KeyD"), kVK_ANSI_F: (33, "KeyF"),
        kVK_ANSI_G: (34, "KeyG"), kVK_ANSI_H: (35, "KeyH"), kVK_ANSI_J: (36, "KeyJ"), kVK_ANSI_K: (37, "KeyK"),
        kVK_ANSI_L: (38, "KeyL"), kVK_ANSI_Semicolon: (39, "Semicolon"), kVK_ANSI_Quote: (40, "Quote"),
        kVK_ANSI_Grave: (41, "Backquote"), kVK_Shift: (42, "ShiftLeft"), kVK_ANSI_Backslash: (43, "Backslash"),
        kVK_ANSI_Z: (44, "KeyZ"), kVK_ANSI_X: (45, "KeyX"), kVK_ANSI_C: (46, "KeyC"), kVK_ANSI_V: (47, "KeyV"),
        kVK_ANSI_B: (48, "KeyB"), kVK_ANSI_N: (49, "KeyN"), kVK_ANSI_M: (50, "KeyM"), kVK_ANSI_Comma: (51, "Comma"),
        kVK_ANSI_Period: (52, "Period"), kVK_ANSI_Slash: (53, "Slash"), kVK_RightShift: (54, "ShiftRight"),
        kVK_Option: (56, "AltLeft"), kVK_Space: (57, "Space"), kVK_CapsLock: (58, "CapsLock"),
        kVK_F1: (59, "F1"), kVK_F2: (60, "F2"), kVK_F3: (61, "F3"), kVK_F4: (62, "F4"), kVK_F5: (63, "F5"),
        kVK_F6: (64, "F6"), kVK_F7: (65, "F7"), kVK_F8: (66, "F8"), kVK_F9: (67, "F9"), kVK_F10: (68, "F10"),
        kVK_F11: (87, "F11"), kVK_F12: (88, "F12"),
        kVK_ANSI_KeypadClear: (69, "NumLock"), kVK_ANSI_Keypad0: (82, "Numpad0"), kVK_ANSI_Keypad1: (79, "Numpad1"),
        kVK_ANSI_Keypad2: (80, "Numpad2"), kVK_ANSI_Keypad3: (81, "Numpad3"), kVK_ANSI_Keypad4: (75, "Numpad4"),
        kVK_ANSI_Keypad5: (76, "Numpad5"), kVK_ANSI_Keypad6: (77, "Numpad6"), kVK_ANSI_Keypad7: (71, "Numpad7"),
        kVK_ANSI_Keypad8: (72, "Numpad8"), kVK_ANSI_Keypad9: (73, "Numpad9"), kVK_ANSI_KeypadPlus: (78, "NumpadAdd"),
        kVK_ANSI_KeypadMinus: (74, "NumpadSubtract"), kVK_ANSI_KeypadMultiply: (55, "NumpadMultiply"),
        kVK_ANSI_KeypadDivide: (3637, "NumpadDivide"), kVK_ANSI_KeypadDecimal: (83, "NumpadDecimal"),
        kVK_ANSI_KeypadEquals: (3597, "NumpadEqual"), kVK_ANSI_KeypadEnter: (3612, "NumpadEnter"),
        kVK_RightControl: (3613, "ControlRight"), kVK_RightOption: (3640, "AltRight"),
        kVK_Home: (3655, "Home"), kVK_PageUp: (3657, "PageUp"), kVK_End: (3663, "End"), kVK_PageDown: (3665, "PageDown"),
        kVK_Help: (3666, "Insert"), kVK_ForwardDelete: (3667, "Delete"), kVK_Command: (3675, "MetaLeft"),
        kVK_RightCommand: (3676, "MetaRight"), kVK_ContextualMenu: (3677, "ContextMenu"),
        kVK_UpArrow: (57416, "ArrowUp"), kVK_LeftArrow: (57419, "ArrowLeft"), kVK_RightArrow: (57421, "ArrowRight"),
        kVK_DownArrow: (57424, "ArrowDown"),
    ]

    private static let wholeFile: [Double] = [0, .infinity]

    struct Problem: Error {
        let reason: String
    }

    struct Definition {
        let file: String
        let down: [Double]
        let up: [Double]?
    }

    let id: String
    let name: String
    let keySounds: [Int: KeySound]
    let unavailableReason: String?

    var isAvailable: Bool { unavailableReason == nil }

    func sound(forKeyCode keyCode: Int?) -> KeySound? {
        keyCode.flatMap { keySounds[$0] } ?? keySounds.values.randomElement()
    }

    static func scan(_ root: URL = folder) -> [KeyboardSoundpack] {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: .skipsHiddenFiles)) ?? []
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { $0.lastPathComponent.caseInsensitiveCompare(MouseSoundpack.folderName) != .orderedSame }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(load)
    }

    static func load(from folder: URL) -> KeyboardSoundpack {
        let id = "pack:" + folder.lastPathComponent
        var name = folder.lastPathComponent
        do {
            let config = try readConfig(in: folder)
            if let configName = config["name"] as? String, !configName.isEmpty { name = String(configName.prefix(80)) }
            let sounds = try keySounds(for: definitions(in: config), folder: folder)
            return KeyboardSoundpack(id: id, name: name, keySounds: sounds, unavailableReason: nil)
        } catch let problem as Problem {
            return KeyboardSoundpack(id: id, name: name, keySounds: [:], unavailableReason: problem.reason)
        } catch {
            return KeyboardSoundpack(id: id, name: name, keySounds: [:], unavailableReason: "Can't read this pack.")
        }
    }

    static func readConfig(in folder: URL) throws -> [String: Any] {
        guard let url = file(named: configFileName, in: folder, maxBytes: maxConfigBytes),
              let data = try? Data(contentsOf: url),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Problem(reason: "Missing or unreadable config.json.")
        }
        return config
    }

    private static func definitions(in config: [String: Any]) throws -> [Int: Definition] {
        let entries: [String: Any]
        let isV2: Bool
        if let definitions = (config["definitions"] ?? config["defs"]) as? [String: Any] {
            entries = definitions
            isV2 = true
        } else if let defines = config["defines"] as? [String: Any] {
            entries = defines
            isV2 = false
        } else {
            throw Problem(reason: unrecognisedFormat)
        }
        guard !entries.isEmpty else { throw Problem(reason: "config.json has no key sounds.") }
        guard entries.count <= maxDefines else { throw Problem(reason: "config.json defines too many keys.") }
        return isV2 ? v2Definitions(entries, config: config) : try v1Definitions(entries, config: config)
    }

    private static func v1Definitions(_ defines: [String: Any], config: [String: Any]) throws -> [Int: Definition] {
        let isMulti: Bool
        switch config["key_define_type"] as? String ?? "single" {
        case "single": isMulti = false
        case "multi": isMulti = true
        default: throw Problem(reason: "Unknown key_define_type in config.json.")
        }
        let sound = config["sound"] as? String ?? ""
        return keyNames.reduce(into: [:]) { definitions, key in
            let define = defines[String(key.value.scancode)]
            if isMulti, let file = define as? String {
                definitions[key.key] = Definition(file: file, down: wholeFile, up: nil)
            } else if !isMulti, let slice = define as? [NSNumber], slice.count == 2 {
                let start = slice[0].doubleValue
                definitions[key.key] = Definition(file: sound, down: [start, start + slice[1].doubleValue], up: nil)
            }
        }
    }

    private static func v2Definitions(_ entries: [String: Any], config: [String: Any]) -> [Int: Definition] {
        keyNames.reduce(into: [:]) { definitions, key in
            definitions[key.key] = v2Definition(entries[key.value.code], config: config)
        }
    }

    static func v2Definition(_ entry: Any?, config: [String: Any]) -> Definition? {
        guard let entry = entry as? [String: Any] else { return nil }
        let isMulti = config["definition_method"] as? String == "multi"
        let entryFile = isMulti ? entry["audio_file"] as? String ?? "" : ""
        let file = entryFile.isEmpty ? config["audio_file"] as? String ?? "" : entryFile
        if isMulti, entry["timing"] == nil {
            return Definition(file: file, down: wholeFile, up: nil)
        }
        guard let timing = (entry["timing"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }),
              (1...2).contains(timing.count) else { return nil }
        return Definition(file: file, down: timing[0], up: timing.count == 2 ? timing[1] : nil)
    }

    static func keySounds<Key: Hashable>(for definitions: [Key: Definition], folder: URL) throws -> [Key: KeySound] {
        var files: [String: AVAudioFile] = [:]
        var slices: [String: AVAudioPCMBuffer] = [:]
        var sounds: [Key: KeySound] = [:]
        var problem = Problem(reason: "No usable sounds.")
        for (key, definition) in definitions {
            if files[definition.file] == nil {
                do {
                    files[definition.file] = try open(definition.file, in: folder)
                } catch let error as Problem {
                    problem = error
                }
            }
            guard let audio = files[definition.file], let down = slice(definition.down, of: audio, cache: &slices) else { continue }
            sounds[key] = KeySound(down: down, up: definition.up.flatMap { slice($0, of: audio, cache: &slices) })
        }
        guard !sounds.isEmpty else { throw problem }
        return sounds
    }

    private static func slice(_ range: [Double], of audio: AVAudioFile, cache: inout [String: AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard range.count == 2 else { return nil }
        let rate = audio.processingFormat.sampleRate
        let start = range[0] / 1000 * rate
        let end = min(range[1] / 1000 * rate, Double(audio.length))
        guard start >= 0, end - start >= 1 else { return nil }
        let first = AVAudioFramePosition(start)
        let last = AVAudioFramePosition(end)
        let key = "\(audio.url.path):\(first)-\(last)"
        if cache[key] == nil {
            cache[key] = read(audio, from: first, frames: last - first)
        }
        return cache[key]
    }

    private static func file(named name: String, in folder: URL, maxBytes: Int) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("/") else { return nil }
        let root = folder.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(name).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/"),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? .max) <= maxBytes else { return nil }
        return url
    }

    static func open(_ name: String, in folder: URL) throws -> AVAudioFile {
        guard let url = file(named: name, in: folder, maxBytes: maxAudioFileBytes) else {
            throw Problem(reason: "Sound file is missing or outside the pack.")
        }
        do {
            return try AVAudioFile(forReading: url)
        } catch {
            throw Problem(reason: url.pathExtension.lowercased() == "ogg" ? unsupportedOGG : "Can't read \(url.lastPathComponent).")
        }
    }

    static func read(_ audio: AVAudioFile, from start: AVAudioFramePosition, frames: AVAudioFramePosition) -> AVAudioPCMBuffer? {
        let capped = AVAudioFrameCount(min(frames, AVAudioFramePosition(maxKeySoundSeconds * audio.processingFormat.sampleRate)))
        guard let source = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: capped) else { return nil }
        do {
            audio.framePosition = start
            try audio.read(into: source, frameCount: capped)
        } catch {
            return nil
        }
        return convert(source)
    }

    private static func convert(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard source.frameLength > 0, let converter = AVAudioConverter(from: source.format, to: format) else { return nil }
        converter.downmix = true
        let capacity = AVAudioFrameCount((Double(source.frameLength) * format.sampleRate / source.format.sampleRate).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var delivered = false
        let status = converter.convert(to: output, error: nil) { _, inputStatus in
            inputStatus.pointee = delivered ? .endOfStream : .haveData
            defer { delivered = true }
            return delivered ? nil : source
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }
}
