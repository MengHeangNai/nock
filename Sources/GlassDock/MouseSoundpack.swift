import AVFoundation

struct MouseSoundpack: Identifiable {
    static let folderName = "Mouse"
    static let folder = KeyboardSoundpack.folder.appendingPathComponent(folderName, isDirectory: true)
    static let audioExtensions: Set<String> = ["wav", "mp3", "m4a", "aif", "aiff", "caf", "ogg"]
    private static let fileSounds: [MouseSound] = [.click, .release, .right, .middle, .scroll]
    private static let wheelPrefixes = ["MouseWheel", "Wheel"]
    static let missingClick = "No click sound file."
    static let missingMouseLeft = "config.json has no MouseLeft sound."
    static let unplayableMouseLeft = "Can't play the MouseLeft sound."

    let id: String
    let name: String
    let sounds: [MouseSound: AVAudioPCMBuffer]
    let unavailableReason: String?

    var isAvailable: Bool { unavailableReason == nil }

    static func scan(_ root: URL = folder) -> [MouseSoundpack] {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: .skipsHiddenFiles)) ?? []
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(load)
    }

    static func load(from folder: URL) -> MouseSoundpack {
        let id = "mouse:" + folder.lastPathComponent
        let fileNames = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        guard fileNames.contains(KeyboardSoundpack.configFileName) else {
            return loadFiles(fileNames, from: folder, id: id)
        }
        return loadMechvibes(from: folder, id: id)
    }

    private static func loadFiles(_ fileNames: [String], from folder: URL, id: String) -> MouseSoundpack {
        var sounds: [MouseSound: AVAudioPCMBuffer] = [:]
        var clickProblem = missingClick
        for sound in fileSounds {
            guard let fileName = fileNames.first(where: { isAudioFile($0, for: sound) }) else { continue }
            do {
                let audio = try KeyboardSoundpack.open(fileName, in: folder)
                sounds[sound] = KeyboardSoundpack.read(audio, from: 0, frames: audio.length)
            } catch {
                if sound == .click { clickProblem = (error as? KeyboardSoundpack.Problem)?.reason ?? clickProblem }
            }
        }
        let name = folder.lastPathComponent
        guard let click = sounds[.click] else {
            return MouseSoundpack(id: id, name: name, sounds: [:], unavailableReason: clickProblem)
        }
        let release = sounds[.release] ?? click
        return MouseSoundpack(id: id, name: name, sounds: [
            .click: click, .release: release,
            .right: sounds[.right] ?? click, .rightRelease: release,
            .middle: sounds[.middle] ?? click, .middleRelease: release,
            .scroll: sounds[.scroll] ?? click,
        ], unavailableReason: nil)
    }

    private static func loadMechvibes(from folder: URL, id: String) -> MouseSoundpack {
        var name = folder.lastPathComponent
        do {
            let config = try KeyboardSoundpack.readConfig(in: folder)
            if let configName = config["name"] as? String, !configName.isEmpty { name = String(configName.prefix(80)) }
            guard let entries = (config["definitions"] ?? config["defs"]) as? [String: Any] else {
                throw KeyboardSoundpack.Problem(reason: KeyboardSoundpack.unrecognisedFormat)
            }
            let definitions = [
                MouseSound.click: KeyboardSoundpack.v2Definition(entries["MouseLeft"], config: config),
                .right: KeyboardSoundpack.v2Definition(entries["MouseRight"], config: config),
                .middle: KeyboardSoundpack.v2Definition(entries["MouseMiddle"], config: config),
                .scroll: wheelDefinition(in: entries, config: config),
            ].compactMapValues { $0 }
            guard definitions[.click] != nil else { throw KeyboardSoundpack.Problem(reason: missingMouseLeft) }
            let buttons = try KeyboardSoundpack.keySounds(for: definitions, folder: folder)
            guard let left = buttons[.click] else { throw KeyboardSoundpack.Problem(reason: unplayableMouseLeft) }
            let right = buttons[.right] ?? left
            let middle = buttons[.middle] ?? left
            let sounds: [MouseSound: AVAudioPCMBuffer?] = [
                .click: left.down, .release: left.up,
                .right: right.down, .rightRelease: right.up,
                .middle: middle.down, .middleRelease: middle.up,
                .scroll: buttons[.scroll]?.down ?? left.down,
            ]
            return MouseSoundpack(id: id, name: name, sounds: sounds.compactMapValues { $0 }, unavailableReason: nil)
        } catch let problem as KeyboardSoundpack.Problem {
            return MouseSoundpack(id: id, name: name, sounds: [:], unavailableReason: problem.reason)
        } catch {
            return MouseSoundpack(id: id, name: name, sounds: [:], unavailableReason: "Can't read this pack.")
        }
    }

    private static func wheelDefinition(in entries: [String: Any], config: [String: Any]) -> KeyboardSoundpack.Definition? {
        entries.keys.sorted()
            .filter { key in wheelPrefixes.contains { key.hasPrefix($0) } }
            .lazy
            .compactMap { KeyboardSoundpack.v2Definition(entries[$0], config: config) }
            .first
    }

    private static func isAudioFile(_ fileName: String, for sound: MouseSound) -> Bool {
        let url = URL(fileURLWithPath: fileName)
        return url.deletingPathExtension().lastPathComponent.lowercased() == sound.rawValue
            && audioExtensions.contains(url.pathExtension.lowercased())
    }
}
