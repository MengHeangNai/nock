import SwiftUI
import AppKit

struct KeyboardTab: View {
    @ObservedObject var sounds: KeyboardSoundController
    @ObservedObject var settings: DockSettings
    @State private var showsMouse = false

    private var selectedID: Binding<String> { showsMouse ? $settings.mouseSoundID : $settings.keyboardSoundID }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            controls
            soundList
        }
        .onAppear { sounds.rescanPacks() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                deviceButton("Keyboard", isMouse: false)
                deviceButton("Mouse", isMouse: true)
            }
            if showsMouse {
                volumeSlider($settings.mouseSoundVolume)
                Toggle("Scroll sounds", isOn: $settings.mouseScrollSounds)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 12))
            } else {
                Toggle("Keyboard sounds", isOn: $settings.keyboardSoundsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 13, weight: .semibold))
                volumeSlider($settings.keyboardSoundVolume)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button("Open Folder") { NSWorkspace.shared.open(showsMouse ? MouseSoundpack.folder : KeyboardSoundpack.folder) }
                if !showsMouse {
                    Button("Get Packs") {
                        if let url = URL(string: "https://mechvibes.com/sound-packs/") { NSWorkspace.shared.open(url) }
                    }
                }
                Button { sounds.rescanPacks() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Rescan sound packs")
                    .hoverLabel("Rescan", edge: .top)
            }
            .buttonStyle(IslandButtonStyle())
        }
        .frame(width: 250, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    private func deviceButton(_ title: String, isMouse: Bool) -> some View {
        let isSelected = showsMouse == isMouse
        return Button { showsMouse = isMouse } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(isSelected ? Color.white.opacity(0.16) : .clear, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeOut(duration: 0.2), value: showsMouse)
    }

    private func volumeSlider(_ volume: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
            Slider(value: volume, in: 0...1)
                .controlSize(.mini)
                .accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private var soundList: some View {
        ScrollView {
            VStack(spacing: 2) {
                if showsMouse {
                    row(id: MouseSoundProfile.offID, name: "Off", unavailableReason: nil)
                    row(id: MouseSoundProfile.matchKeyboardID, name: "Match keyboard", unavailableReason: nil)
                    ForEach(MouseSoundProfile.allCases) { row(id: $0.rawValue, name: $0.title, unavailableReason: nil) }
                    ForEach(sounds.mousePacks) { row(id: $0.id, name: $0.name, unavailableReason: $0.unavailableReason) }
                    if sounds.mousePacks.isEmpty {
                        hint("Put a folder with click.wav, plus optional release, right and scroll files, into the folder from Open Folder.")
                    }
                } else {
                    ForEach(KeyboardSoundProfile.allCases) { row(id: $0.rawValue, name: $0.title, unavailableReason: nil) }
                    ForEach(sounds.packs) { row(id: $0.id, name: $0.name, unavailableReason: $0.unavailableReason) }
                    if sounds.packs.isEmpty {
                        hint("Download Mechvibes sound packs and unzip each one into the folder from Open Folder.")
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedID.wrappedValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
    }

    private func row(id: String, name: String, unavailableReason: String?) -> some View {
        let isSelected = selectedID.wrappedValue == id
        return HStack(spacing: 8) {
            Button { selectedID.wrappedValue = id } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(isSelected ? 1 : 0)
                    Text(name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if let unavailableReason {
                        Text(unavailableReason)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(unavailableReason != nil)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            if unavailableReason == nil && id != MouseSoundProfile.offID {
                Button { showsMouse ? sounds.previewMouse(id) : sounds.preview(id) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(name)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(isSelected ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(unavailableReason == nil ? 1 : 0.55)
    }
}
