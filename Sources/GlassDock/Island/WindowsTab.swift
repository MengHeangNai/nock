import SwiftUI
import AppKit

struct WindowsTab: View {
    @ObservedObject var controller: PinnedWindowController
    @ObservedObject var pip: PiPController

    var body: some View {
        Group {
            if !controller.isTrusted {
                accessPrompt
            } else if controller.windows.isEmpty {
                Text("No open windows")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .onAppear {
            controller.startListing()
            pip.watchAccess()
        }
        .onDisappear {
            controller.stopListing()
            pip.stopWatchingAccess()
        }
    }

    private var accessPrompt: some View {
        VStack(spacing: 10) {
            Text("Pinning and moving windows needs Accessibility access, so GlassDock can list other apps' windows and move them. It never records your screen.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings…") {
                AppWindows.requestAccess()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(IslandButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var screenAccessNote: some View {
        HStack(spacing: 8) {
            Text("Picture in Picture needs Screen Recording access. GlassDock only shows the window on your screen; frames are never saved or sent.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Settings…") { pip.openScreenRecordingSettings() }
                .buttonStyle(IslandButtonStyle())
        }
    }

    private var list: some View {
        VStack(spacing: 6) {
            if pip.needsScreenAccess { screenAccessNote }
            if let failure = pip.failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !pip.active.isEmpty {
                HStack {
                    Label("\(pip.active.count) in Picture in Picture", systemImage: "pip.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.mint)
                    Spacer()
                    Button("Close all PiPs") { pip.closeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if !controller.pinned.isEmpty {
                HStack {
                    Label("\(controller.pinned.count) pinned", systemImage: "pin.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Unpin all") { controller.unpinAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(controller.windows) { window in
                        WindowRow(window: window, controller: controller, pip: pip)
                    }
                }
            }
        }
    }
}

private struct WindowRow: View {
    let window: OpenWindow
    @ObservedObject var controller: PinnedWindowController
    @ObservedObject var pip: PiPController

    var body: some View {
        let isPinned = controller.isPinned(window)
        let hasPiP = pip.isActive(window)
        let pipBlock = pip.block(for: window)

        HStack(spacing: 8) {
            Image(nsImage: window.icon ?? NSImage())
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(window.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                    if hasPiP {
                        Image(systemName: "pip.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.mint)
                            .accessibilityHidden(true)
                    }
                    if pip.isKeptLive(window) {
                        Image(systemName: "display")
                            .font(.system(size: 9))
                            .foregroundStyle(.mint)
                            .hoverLabel("Kept on hidden screen while in PiP", edge: .top)
                            .accessibilityLabel("Kept on hidden screen while in Picture in Picture")
                    }
                }
                Text(window.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if pip.looksProtected(window) {
                    Text(PiPFrameProbe.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                if let error = controller.raiseErrors[window.id] {
                    Text("Couldn't bring this window forward (Accessibility error \(error.rawValue))")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button { controller.togglePin(window) } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 22)
                    .foregroundStyle(isPinned ? Color.orange : Color.white.opacity(0.6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(window.isMinimized && !isPinned)
            .hoverLabel(isPinned ? "Unpin" : "Pin in front", edge: .top)
            .accessibilityLabel(isPinned ? "Unpin \(window.title)" : "Pin \(window.title) in front")
            Button { pip.toggle(window) } label: {
                Image(systemName: hasPiP ? "pip.exit" : "pip.enter")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 22)
                    .foregroundStyle(hasPiP ? Color.mint : Color.white.opacity(0.6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pipBlock != nil && !hasPiP)
            .hoverLabel(pipBlock?.reason ?? (hasPiP ? "Close Picture in Picture" : "Picture in Picture"), edge: .top)
            .accessibilityLabel(hasPiP ? "Close Picture in Picture of \(window.title)" : "Show \(window.title) in Picture in Picture")
            snapMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(isPinned || hasPiP ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(window.isMinimized ? 0.5 : 1)
    }

    private var snapMenu: some View {
        Menu {
            ForEach(SnapPreset.allCases) { preset in
                Button { controller.snap(window, to: preset) } label: {
                    Label(preset.title, systemImage: preset.symbol)
                }
            }
            if NSScreen.physicalScreens.count > 1 {
                Divider()
                Button { controller.moveToNextDisplay(window) } label: {
                    Label("Move to Next Display", systemImage: "display")
                }
            }
        } label: {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 12))
                .frame(width: 26, height: 22)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(window.isMinimized)
        .accessibilityLabel("Move or resize \(window.title)")
    }
}
