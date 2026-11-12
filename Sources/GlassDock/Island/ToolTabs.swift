import SwiftUI
import AppKit

// MARK: - Terminal

struct TerminalTab: View {
    @ObservedObject var terminal: TerminalSession
    @State private var command = ""
    @State private var historyIndex: Int?

    var body: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(terminal.output.isEmpty
                         ? "Run a command below. Interactive programs like vim or top aren't supported."
                         : terminal.output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(terminal.output.isEmpty ? Color.secondary : Color.white.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: terminal.output) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .padding(8)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 6) {
                Text(terminal.prompt)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                TextField("", text: $command)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        terminal.run(command)
                        command = ""
                        historyIndex = nil
                    }
                    .onKeyPress(.upArrow) { recall(-1); return .handled }
                    .onKeyPress(.downArrow) { recall(1); return .handled }
                if terminal.isRunning {
                    Button("Stop") { terminal.interrupt() }
                        .buttonStyle(IslandButtonStyle())
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func recall(_ delta: Int) {
        let history = terminal.history
        guard !history.isEmpty else { return }
        let index = min(max((historyIndex ?? history.count) + delta, 0), history.count)
        historyIndex = index
        command = index < history.count ? history[index] : ""
    }
}

// MARK: - Color Picker

struct ColorPickerTab: View {
    @ObservedObject var colors: ColorPickerStore
    @State private var copied: String?

    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colors.current.map { Color(nsColor: $0) } ?? Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
                    .frame(width: 96, height: 96)
                Button { colors.pick() } label: { Label("Pick", systemImage: "eyedropper") }
                    .buttonStyle(IslandButtonStyle())
            }

            VStack(alignment: .leading, spacing: 6) {
                if let color = colors.current {
                    formatRow("HEX", ColorPickerStore.hex(color))
                    formatRow("RGB", ColorPickerStore.rgb(color))
                    formatRow("HSL", ColorPickerStore.hsl(color))
                } else {
                    Text("Pick a color from anywhere on screen. Its HEX value is copied for you.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if !colors.recent.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(colors.recent, id: \.self) { hex in
                            if let swatch = ColorPickerStore.color(fromHex: hex) {
                                Circle()
                                    .fill(Color(nsColor: swatch))
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2)))
                                    .frame(width: 18, height: 18)
                                    .onTapGesture { colors.select(swatch) }
                                    .hoverLabel(hex, edge: .top)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatRow(_ label: String, _ value: String) -> some View {
        Button {
            colors.copy(value)
            copied = value
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                Text(value).font(.system(size: 13, design: .monospaced))
                Spacer()
                Text(copied == value ? "Copied" : "Copy")
                    .font(.system(size: 10))
                    .foregroundStyle(copied == value ? Color.green : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keep Awake

struct KeepAwakeTab: View {
    @ObservedObject var keepAwake: KeepAwake

    var body: some View {
        HStack(spacing: 22) {
            Button {
                if keepAwake.isOn { keepAwake.disable() } else { keepAwake.enable(for: nil) }
            } label: {
                Image(systemName: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 34))
                    .foregroundStyle(keepAwake.isOn ? Color.orange : Color.secondary)
                    .frame(width: 92, height: 92)
                    .background(Circle().fill(Color.white.opacity(keepAwake.isOn ? 0.12 : 0.06)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text(keepAwake.isOn ? "Keeping your Mac awake" : "Keep Awake is off")
                    .font(.system(size: 16, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach([15, 30, 60, 120, 240], id: \.self) { minutes in
                        Button(minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h") {
                            keepAwake.enable(for: TimeInterval(minutes * 60))
                        }
                    }
                    Button("∞") { keepAwake.enable(for: nil) }
                    if keepAwake.isOn {
                        Button("Turn Off") { keepAwake.disable() }
                    }
                }
                .buttonStyle(IslandButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        guard keepAwake.isOn else { return "Your Mac and display sleep as usual." }
        if let until = keepAwake.until {
            return "Until \(until.formatted(date: .omitted, time: .shortened))"
        }
        return "Until you turn it off"
    }
}

// MARK: - Downloads

struct DownloadsTab: View {
    @ObservedObject var downloads: DownloadsWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent downloads")
                Spacer()
                Button("Open Downloads") { NSWorkspace.shared.open(downloads.folder) }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if downloads.items.isEmpty {
                IslandMessage(text: "Nothing in Downloads yet", systemImage: "arrow.down.circle")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(downloads.items) { item in
                            DownloadTile(item: item, downloads: downloads)
                        }
                    }
                }
            }
        }
        .onAppear { downloads.start() }
        .onDisappear { downloads.stop() }
    }
}

private struct DownloadTile: View {
    let item: DownloadsWatcher.Item
    let downloads: DownloadsWatcher

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                    .opacity(item.inProgress ? 0.5 : 1)
                if item.inProgress { ProgressView().controlSize(.small) }
            }
            Text(item.displayName)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(item.inProgress ? "Downloading…" : Self.relative.localizedString(for: item.added, relativeTo: Date()))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(width: 84)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Move to Trash") { downloads.moveToTrash(item) }
        }
        .help(item.url.lastPathComponent)
    }
}

// MARK: - Devices

struct DevicesTab: View {
    @ObservedObject var devices: DevicesService
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let level = battery.level {
                    DeviceCard(name: "This Mac", symbol: "laptopcomputer",
                               batteries: [.init(label: "", level: level)], charging: battery.isPluggedIn)
                }
                ForEach(devices.devices) { device in
                    DeviceCard(name: device.name, symbol: device.symbol, batteries: device.batteries, charging: false)
                }
                if !devices.hasLoaded {
                    ProgressView().controlSize(.small).frame(width: 80)
                } else if devices.devices.isEmpty {
                    Text("No Bluetooth devices connected")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear { devices.start() }
        .onDisappear { devices.stop() }
    }
}

private struct DeviceCard: View {
    let name: String
    let symbol: String
    let batteries: [DevicesService.Battery]
    let charging: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol).font(.system(size: 24))
                Spacer()
                if charging { Image(systemName: "bolt.fill").foregroundStyle(.green) }
            }
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if batteries.isEmpty {
                Text("Connected").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(batteries, id: \.self) { battery in
                    HStack(spacing: 6) {
                        if !battery.label.isEmpty {
                            Text(battery.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .leading)
                        }
                        ProgressView(value: Double(battery.level) / 100)
                            .tint(battery.level <= 20 ? .red : .green)
                        Text("\(battery.level)%")
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 160, alignment: .leading)
        .frame(maxHeight: .infinity)
        .islandCard()
    }
}

// MARK: - Stats

struct StatsTab: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 10) {
            statCard("CPU", symbol: "cpu", value: "\(Int((stats.cpu * 100).rounded()))%") {
                Sparkline(values: stats.cpuHistory)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .frame(height: 40)
            }
            statCard("Memory", symbol: "memorychip",
                     value: SystemStats.bytes(Int64(stats.memoryUsed))) {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(stats.memoryUsed) / Double(max(stats.memoryTotal, 1)))
                        .tint(.blue)
                    Text("of \(SystemStats.bytes(Int64(stats.memoryTotal)))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            statCard("Network", symbol: "network", value: nil) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(SystemStats.rate(stats.downloadRate), systemImage: "arrow.down")
                    Label(SystemStats.rate(stats.uploadRate), systemImage: "arrow.up")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            }
            statCard("Disk", symbol: "internaldrive", value: SystemStats.bytes(stats.diskFree)) {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: stats.diskTotal > 0 ? 1 - Double(stats.diskFree) / Double(stats.diskTotal) : 0)
                        .tint(.orange)
                    Text("free of \(SystemStats.bytes(stats.diskTotal))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func statCard<Content: View>(_ title: String, symbol: String, value: String?,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if let value {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .islandCard()
    }
}

struct Sparkline: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                                y: rect.maxY - rect.height * CGFloat(min(max(value, 0), 1)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
