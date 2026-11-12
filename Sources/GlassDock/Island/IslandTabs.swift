import SwiftUI
import AppKit

struct IslandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color.white.opacity(configuration.isPressed ? 0.24 : 0.12), in: Capsule())
    }
}

// HomeTab and LyricsTab live in NowPlayingTabs.swift.

// MARK: - Clipboard

struct ClipboardTab: View {
    @ObservedObject var clipboard: ClipboardStore
    @State private var query = ""
    @State private var copiedID: UUID?

    private var filtered: [ClipboardStore.Item] {
        let matches = query.isEmpty
            ? clipboard.items
            : clipboard.items.filter { $0.text.localizedCaseInsensitiveContains(query) }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard", text: $query)
                    .textFieldStyle(.plain)
                if clipboard.items.contains(where: { !$0.pinned }) {
                    Button("Clear") { clipboard.clearHistory() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if filtered.isEmpty {
                Text(clipboard.items.isEmpty ? "Text you copy will appear here" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { item in row(item) }
                    }
                }
            }
        }
    }

    private func row(_ item: ClipboardStore.Item) -> some View {
        HStack(spacing: 8) {
            Text(String(item.text.prefix(300)).replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces))
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if copiedID == item.id {
                Text("Copied").font(.system(size: 11)).foregroundStyle(.green)
            }
            Button { clipboard.togglePin(item) } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(item.pinned ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            clipboard.copy(item)
            copiedID = item.id
        }
        .contextMenu {
            Button("Copy") { clipboard.copy(item) }
            Button(item.pinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
            Divider()
            Button("Delete") { clipboard.remove(item) }
        }
    }
}

// MARK: - Timer

struct TimerTab: View {
    @ObservedObject var timer: IslandTimer

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(timer.didFinish ? "Done" : IslandTimer.format(timer.remaining(at: context.date)))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timer.isActive || timer.didFinish ? Color.orange : Color.secondary)
            }

            if timer.isActive {
                HStack(spacing: 8) {
                    Button(timer.isPaused ? "Resume" : "Pause") {
                        timer.isPaused ? timer.resume() : timer.pause()
                    }
                    Button("+1 min") { timer.add(seconds: 60) }
                    Button("Cancel") { timer.cancel() }
                }
                .buttonStyle(IslandButtonStyle())
            } else {
                HStack(spacing: 6) {
                    ForEach([1, 3, 5, 10, 15, 25, 45, 60], id: \.self) { minutes in
                        Button("\(minutes)m") { timer.start(seconds: Double(minutes) * 60) }
                    }
                }
                .buttonStyle(IslandButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

