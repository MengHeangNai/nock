import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: DockSettings
    @ObservedObject var model: DockModel
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var windowAccess = AppWindows.isTrusted
    @State private var recentsAccess = RecentDocuments.isAccessible

    var body: some View {
        Form {
            Section("Modules") {
                Toggle("Dock", isOn: $settings.enableDock)
                Toggle("Island (notch panel)", isOn: $settings.enableIsland)
            }

            Section {
                Toggle("Show lyrics", isOn: $settings.showLyrics)
                Toggle("Show Claude Code plan limits", isOn: $settings.claudeLimitsEnabled)
            } header: {
                Text("Island")
            } footer: {
                Text("Lyrics are looked up on lrclib.net, a free lyrics library. Only the song's title, artist, album and length are sent. Plan limits use the sign-in Claude Code keeps in your Keychain (macOS asks first) and are requested only from Anthropic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Island Tabs") {
                ForEach(IslandTab.allCases.filter { $0 != .home }) { tab in
                    Toggle(isOn: Binding(
                        get: { !settings.hiddenIslandTabs.contains(tab.rawValue) },
                        set: { shown in
                            settings.hiddenIslandTabs.removeAll { $0 == tab.rawValue }
                            if !shown { settings.hiddenIslandTabs.append(tab.rawValue) }
                        }
                    )) {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                }
            }

            // Mirrors System Settings → Desktop & Dock.
            Section("Dock") {
                Slider(value: $settings.iconSize, in: 32...96) {
                    Text("Size")
                } minimumValueLabel: {
                    Text("Small").font(.caption)
                } maximumValueLabel: {
                    Text("Large").font(.caption)
                }
                Toggle("Magnification", isOn: $settings.magnification)
                Slider(value: $settings.maxScale, in: 1.2...2.2) {
                    Text("Magnification size")
                } minimumValueLabel: {
                    Text("Small").font(.caption)
                } maximumValueLabel: {
                    Text("Large").font(.caption)
                }
                .disabled(!settings.magnification)
                Toggle("Automatically hide and show the Dock", isOn: $settings.autoHide)
                Toggle("Animate opening applications", isOn: $settings.animateOpening)
                Toggle("Show indicators for open applications", isOn: $settings.showIndicators)
                Toggle("Show open apps that aren't kept in the Dock", isOn: $settings.showRunningApps)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show app windows in Dock menus")
                        Text(windowAccess
                             ? "Allowed. Right-click an open app to see and switch to its windows."
                             : "Needs Accessibility access in Privacy & Security.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if windowAccess {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { AppWindows.requestAccess() }
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show recent documents in Dock menus")
                        Text(recentsAccess
                             ? "Allowed. Right-click an app that isn't open to see its recent documents."
                             : "Needs Full Disk Access in Privacy & Security: macOS keeps each app's recent documents in a protected folder. Add GlassDock there, then quit and reopen it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if recentsAccess {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                    windowAccess = AppWindows.isTrusted
                    recentsAccess = RecentDocuments.isAccessible
                }
            }

            Section("Dock Widgets") {
                Toggle("Now Playing (Music and Spotify)", isOn: $settings.showNowPlaying)
                Toggle("Battery", isOn: $settings.showBattery)
                Toggle("Clock", isOn: $settings.showClock)
            }

            Section("Dock Apps") {
                ForEach(Array(settings.pinnedPaths.enumerated()), id: \.element) { index, path in
                    pinnedRow(path: path, index: index)
                }
                HStack {
                    Button("Add Apps…", action: addApps)
                    Spacer()
                    Button("Reset to macOS Dock Apps") {
                        settings.pinnedPaths = DockSettings.defaultPinnedPaths()
                    }
                }
            }

            Section("System") {
                Toggle("Hide the macOS Dock while GlassDock is running", isOn: $settings.hideSystemDock)
                    .onChange(of: settings.hideSystemDock) { _, hide in
                        if hide { SystemDock.hide() } else { SystemDock.restore() }
                    }
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("GlassDock: login item change failed: \(error.localizedDescription)")
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }

    private func pinnedRow(path: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
            Text(displayName(path))
            Spacer()
            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == settings.pinnedPaths.count - 1)
            Button { settings.pinnedPaths.remove(at: index) } label: { Image(systemName: "minus.circle") }
        }
        .buttonStyle(.borderless)
    }

    private func displayName(_ path: String) -> String {
        let name = FileManager.default.displayName(atPath: path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard settings.pinnedPaths.indices.contains(target) else { return }
        settings.pinnedPaths.swapAt(index, target)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if !settings.pinnedPaths.contains(path) {
                settings.pinnedPaths.append(path)
            }
        }
    }
}
