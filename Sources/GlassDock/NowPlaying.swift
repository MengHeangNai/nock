import AppKit
import SwiftUI

/// Tracks what Music, Spotify or any other app (a browser tab, for example) is playing: title, artwork, position, and playback controls.
final class NowPlayingMonitor: ObservableObject {
    struct Player: Equatable {
        let bundleID: String
        let displayName: String

        static let music = Player(bundleID: "com.apple.Music", displayName: "Apple Music")
        static let spotify = Player(bundleID: "com.spotify.client", displayName: "Spotify")
        static let native = [music, spotify]

        var isNative: Bool { Self.native.contains { $0.bundleID == bundleID } }

        var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    }

    private struct SystemSnapshot: Decodable {
        let pid: Int32?
        let playing: Bool?
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        let timestamp: Double?
        let artwork: String?
    }

    private enum SystemCommand: Int {
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    private static let perlLoader = """
    my $handle = DynaLoader::dl_load_file($ARGV[0], 0) or die "cannot load $ARGV[0]";
    my $symbol = DynaLoader::dl_find_symbol($handle, $ARGV[1]) or die "missing $ARGV[1]";
    DynaLoader::dl_install_xsub("main::run", $symbol);
    run();
    """

    static let defaultAccent = Color(nsColor: .systemPink)

    @Published private(set) var player: Player?
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var album: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var playerIcon: NSImage?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor = NowPlayingMonitor.defaultAccent
    @Published private(set) var palette = VisualizerPalette.neutral
    /// Track length in seconds; 0 while unknown.
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var runningPlayers: [Player] = []

    // Position is interpolated locally from the last known value, and re-synced every few seconds.
    @Published private(set) var positionAnchor: TimeInterval = 0
    @Published private(set) var anchorDate = Date()

    /// Players installed on this Mac, in menu order.
    let installedPlayers: [Player] = Player.native.filter { $0.appURL != nil }

    private let scriptQueue = DispatchQueue(label: "GlassDock.AppleScript")
    private var syncTimer: Timer?
    private var artworkKey: String?
    private var systemStream: Process?
    private var systemBuffer = Data()

    init() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(musicChanged(_:)),
                                name: .init("com.apple.Music.playerInfo"), object: nil)
        distributed.addObserver(self, selector: #selector(spotifyChanged(_:)),
                                name: .init("com.spotify.client.PlaybackStateChanged"), object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appTerminated(_:)),
                              name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appLaunched(_:)),
                              name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        refreshRunningPlayers()

        syncTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            self.syncPosition()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.queryRunningPlayers() }
        startSystemStream()
    }

    deinit { systemStream?.terminate() }

    func position(at date: Date = Date()) -> TimeInterval {
        let value = isPlaying ? positionAnchor + date.timeIntervalSince(anchorDate) : positionAnchor
        return duration > 0 ? min(max(0, value), duration) : max(0, value)
    }

    // MARK: Notifications

    @objc private func musicChanged(_ note: Notification) { update(from: note.userInfo, player: .music) }
    @objc private func spotifyChanged(_ note: Notification) { update(from: note.userInfo, player: .spotify) }

    @objc private func appLaunched(_ note: Notification) {
        refreshRunningPlayers()
    }

    @objc private func appTerminated(_ note: Notification) {
        refreshRunningPlayers()
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier, id == player?.bundleID { clear() }
    }

    private func refreshRunningPlayers() {
        let running = Player.native.filter(isRunning)
        if running != runningPlayers { runningPlayers = running }
    }

    private func update(from info: [AnyHashable: Any]?, player newPlayer: Player) {
        let state = info?["Player State"] as? String ?? "Stopped"
        if state == "Stopped" {
            if player == newPlayer { clear() }
            return
        }
        // Don't let a paused player replace one that is actively playing.
        if state != "Playing", isPlaying, player != newPlayer { return }

        let previousPosition = position()
        let playerChanged = player != newPlayer
        if playerChanged {
            player = newPlayer
            playerIcon = newPlayer.appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        }

        let newTitle = info?["Name"] as? String
        let newArtist = info?["Artist"] as? String
        let newAlbum = info?["Album"] as? String
        let trackChanged = playerChanged || newTitle != title || newArtist != artist || newAlbum != album
        title = newTitle
        artist = newArtist
        album = newAlbum

        // Both apps report the length in milliseconds ("Total Time" for Music, "Duration" for Spotify).
        if let ms = (info?["Total Time"] ?? info?["Duration"]) as? NSNumber, ms.doubleValue > 0 {
            duration = ms.doubleValue / 1000
        } else if trackChanged {
            duration = 0
        }

        let wasPlaying = isPlaying
        isPlaying = state == "Playing"

        if let seconds = info?["Playback Position"] as? NSNumber {
            setPosition(seconds.doubleValue)
        } else if trackChanged {
            setPosition(0)
        } else if wasPlaying != isPlaying {
            setPosition(previousPosition)
        }

        if trackChanged {
            artwork = nil
            palette = .neutral
            updateAccent(from: nil)
            loadArtwork()
        }
        syncPosition()
    }

    private func setPosition(_ seconds: TimeInterval) {
        positionAnchor = seconds
        anchorDate = Date()
    }

    private func clear() {
        player = nil
        title = nil
        artist = nil
        album = nil
        isPlaying = false
        playerIcon = nil
        artwork = nil
        artworkKey = nil
        accentColor = Self.defaultAccent
        palette = .neutral
        duration = 0
        setPosition(0)
    }

    /// Reads the current track from players that are already running when GlassDock starts.
    private func queryRunningPlayers() {
        for candidate in Player.native where isRunning(candidate) {
            let source = """
            tell application id "\(candidate.bundleID)"
                set s to player state as text
                if s is "stopped" then return "stopped"
                set t to current track
                return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t)
            end tell
            """
            runScript(source) { [weak self] output in
                guard let lines = output?.components(separatedBy: "\n"), lines.count >= 4 else { return }
                self?.update(from: ["Player State": lines[0].capitalized, "Name": lines[1],
                                    "Artist": lines[2], "Album": lines[3]],
                             player: candidate)
            }
        }
    }

    /// Asks the player for its exact position and the track length.
    private func syncPosition() {
        guard let player, player.isNative, isRunning(player) else { return }
        let durationExpression = player == .spotify
            ? "((duration of current track) / 1000)"
            : "(duration of current track)"
        let source = """
        tell application id "\(player.bundleID)"
            return ((player position) as text) & linefeed & (\(durationExpression) as text)
        end tell
        """
        runScript(source) { [weak self] output in
            guard let self, self.player == player, let output else { return }
            let parts = output.components(separatedBy: "\n").map {
                Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
            }
            if parts.count >= 2, let length = parts[1], length > 0 { self.duration = length }
            if let position = parts.first ?? nil { self.setPosition(position) }
        }
    }

    // MARK: Artwork

    private func loadArtwork() {
        guard let player else { return }
        let key = [title, artist, album].map { $0 ?? "" }.joined(separator: "\n")
        artworkKey = key

        switch player {
        case .spotify:
            runScript("tell application id \"com.spotify.client\" to return artwork url of current track") { [weak self] output in
                guard let self, self.artworkKey == key,
                      let output, let url = URL(string: output.trimmingCharacters(in: .whitespacesAndNewlines)),
                      url.scheme == "https" else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        if self.artworkKey == key { self.setArtwork(image) }
                    }
                }.resume()
            }
        case .music:
            let source = """
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
                return ""
            end tell
            """
            runDescriptorScript(source) { [weak self] descriptor in
                guard let self, self.artworkKey == key,
                      let data = descriptor?.data, let image = NSImage(data: data) else { return }
                self.setArtwork(image)
            }
        default:
            break
        }
    }

    private func setArtwork(_ image: NSImage) {
        artwork = image
        palette = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(VisualizerPalette.init(image:)) ?? .neutral
        updateAccent(from: image)
    }

    /// Picks a bright accent from the artwork's average color (or the player icon's).
    private func updateAccent(from image: NSImage?) {
        guard let source = image ?? playerIcon,
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            accentColor = Self.defaultAccent
            return
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return }

        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for index in 0..<64 {
            let alpha = Double(pixels[index * 4 + 3]) / 255
            guard alpha > 0.1 else { continue }
            red += Double(pixels[index * 4]) / 255
            green += Double(pixels[index * 4 + 1]) / 255
            blue += Double(pixels[index * 4 + 2]) / 255
            weight += alpha
        }
        guard weight > 0 else { return }

        let average = NSColor(deviceRed: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.12 {
            accentColor = .white
        } else {
            accentColor = Color(nsColor: NSColor(hue: hue, saturation: min(1, max(saturation * 1.2, 0.45)),
                                                 brightness: max(brightness, 0.9), alpha: 1))
        }
    }

    // MARK: Controls

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    /// The player to use without asking: the one already playing, the only one open,
    /// or the only one installed. nil means the user should choose.
    private var automaticPlayer: Player? {
        if let player { return player }
        if runningPlayers.count == 1 { return runningPlayers[0] }
        if installedPlayers.count == 1 { return installedPlayers[0] }
        return nil
    }

    func playPause() {
        if let player, !player.isNative { send(.togglePlayPause); return }
        guard let target = automaticPlayer else { choosePlayer(); return }
        if isRunning(target) {
            if player == target { setPosition(position()) }
            runScript("tell application id \"\(target.bundleID)\" to playpause")
        } else {
            play(with: target)
        }
    }

    func next() {
        if let player, !player.isNative { send(.next); return }
        guard let target = automaticPlayer ?? runningPlayers.first, isRunning(target) else { return }
        runScript("tell application id \"\(target.bundleID)\" to next track")
    }

    func previous() {
        if let player, !player.isNative { send(.previous); return }
        guard let target = automaticPlayer ?? runningPlayers.first, isRunning(target) else { return }
        runScript("tell application id \"\(target.bundleID)\" to previous track")
    }

    func seek(to seconds: TimeInterval) {
        guard let player, isRunning(player) else { return }
        let target = duration > 0 ? min(max(0, seconds), duration) : max(0, seconds)
        setPosition(target)
        if !player.isNative {
            runMediaRemote("glassdock_seek", environment: ["GLASSDOCK_MR_SECONDS": String(target)])
            return
        }
        let value = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), target)
        runScript("tell application id \"\(player.bundleID)\" to set player position to \(value)")
    }

    /// Clicking the artwork: bring the player forward, or pick one when it isn't obvious which.
    func openPlayer() {
        guard let target = automaticPlayer else { choosePlayer(); return }
        if isRunning(target), let url = target.appURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            play(with: target)
        }
    }

    /// Starts playback in the given player, opening it first if needed.
    func play(with target: Player) {
        let script = "tell application id \"\(target.bundleID)\" to play"
        if isRunning(target) {
            runScript(script)
            return
        }
        guard let url = target.appURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            guard error == nil else { return }
            // Give the app a moment to finish launching before asking it to play.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.runScript(script) }
        }
    }

    /// Shows an "Apple Music / Spotify" menu at the cursor.
    private func choosePlayer() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Play with", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for candidate in installedPlayers {
            let item = NSMenuItem(title: candidate.displayName, action: #selector(playerChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.bundleID
            if let url = candidate.appURL, let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func playerChosen(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let chosen = Player.native.first(where: { $0.bundleID == raw }) else { return }
        play(with: chosen)
    }

    private func mediaRemoteProcess(_ symbol: String, environment: [String: String] = [:]) -> Process? {
        guard let library = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("libGlassDockMediaRemote.dylib"),
            FileManager.default.fileExists(atPath: library.path) else { return nil }
        let process = Process()
        // macOS only lets Apple-signed processes use MediaRemote, so the helper library is loaded inside perl.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-MDynaLoader", "-e", Self.perlLoader, library.path, symbol]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        return process
    }

    private func runMediaRemote(_ symbol: String, environment: [String: String]) {
        try? mediaRemoteProcess(symbol, environment: environment)?.run()
    }

    private func send(_ command: SystemCommand) {
        runMediaRemote("glassdock_send", environment: ["GLASSDOCK_MR_COMMAND": String(command.rawValue)])
    }

    private func startSystemStream() {
        guard let process = mediaRemoteProcess("glassdock_stream") else { return }
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consumeSystemOutput(chunk) }
        }
        do {
            try process.run()
            systemStream = process
        } catch {
            NSLog("GlassDock MediaRemote error: \(error)")
        }
    }

    private func consumeSystemOutput(_ chunk: Data) {
        systemBuffer.append(chunk)
        while let newline = systemBuffer.firstIndex(of: 0x0A) {
            let line = systemBuffer[..<newline]
            systemBuffer.removeSubrange(...newline)
            update(fromSystem: try? JSONDecoder().decode(SystemSnapshot.self, from: line))
        }
    }

    private func update(fromSystem snapshot: SystemSnapshot?) {
        guard let snapshot, let pid = snapshot.pid,
              let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier else {
            if let player, !player.isNative { clear() }
            return
        }
        guard !Player.native.contains(where: { $0.bundleID == id }) else { return }

        let source = Player(bundleID: id, displayName: app.localizedName ?? id)
        let playing = snapshot.playing ?? false
        if player != source, !playing || isPlaying { return }

        var info: [AnyHashable: Any] = ["Player State": playing ? "Playing" : "Paused"]
        info["Name"] = snapshot.title
        info["Artist"] = snapshot.artist
        info["Album"] = snapshot.album
        if let duration = snapshot.duration { info["Total Time"] = NSNumber(value: duration * 1000) }
        if let elapsed = snapshot.elapsedTime {
            let age = playing ? snapshot.timestamp.map { Date().timeIntervalSince1970 - $0 } ?? 0 : 0
            info["Playback Position"] = NSNumber(value: elapsed + max(0, age))
        }
        update(from: info, player: source)

        if let encoded = snapshot.artwork, let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            setArtwork(image)
        }
    }

    // MARK: AppleScript

    private func runScript(_ source: String, completion: ((String?) -> Void)? = nil) {
        runDescriptorScript(source) { descriptor in completion?(descriptor?.stringValue) }
    }

    private func runDescriptorScript(_ source: String, completion: @escaping (NSAppleEventDescriptor?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { NSLog("GlassDock AppleScript error: \(error)") }
            let output = error == nil ? result : nil
            DispatchQueue.main.async { completion(output) }
        }
    }
}
