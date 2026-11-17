import SwiftUI
import AppKit

struct KeyboardTab: View {
    @ObservedObject var sounds: KeyboardSoundController
    @ObservedObject var settings: DockSettings

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            controls
            soundList
        }
        .onAppear { sounds.rescanPacks() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Keyboard sounds", isOn: $settings.keyboardSoundsEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                Slider(value: $settings.keyboardSoundVolume, in: 0...1)
                    .controlSize(.mini)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button("Open Folder") { NSWorkspace.shared.open(KeyboardSoundpack.folder) }
                Button("Get Packs") {
                    if let url = URL(string: "https://mechvibes.com/sound-packs/") { NSWorkspace.shared.open(url) }
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

    private var soundList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(KeyboardSoundProfile.allCases) { row(id: $0.rawValue, name: $0.title, unavailableReason: nil) }
                ForEach(sounds.packs) { row(id: $0.id, name: $0.name, unavailableReason: $0.unavailableReason) }
                if sounds.packs.isEmpty {
                    Text("Download Mechvibes sound packs and unzip each one into the folder from Open Folder.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: settings.keyboardSoundID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(id: String, name: String, unavailableReason: String?) -> some View {
        let isSelected = settings.keyboardSoundID == id
        return HStack(spacing: 8) {
            Button { settings.keyboardSoundID = id } label: {
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
            if unavailableReason == nil {
                Button { sounds.preview(id) } label: {
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
