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
    @State private var status: RowStatus?

    private struct RowStatus {
        let id: UUID
        let message: String
        let isFailure: Bool
    }

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
            if let status, status.id == item.id {
                Text(status.message)
                    .font(.system(size: 11))
                    .foregroundStyle(status.isFailure ? Color.red : Color.green)
            }
            Menu { transformItems(item) } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
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
            status = RowStatus(id: item.id, message: "Copied", isFailure: false)
        }
        .contextMenu {
            Button("Copy") { clipboard.copy(item) }
            Menu("Transform") { transformItems(item) }
            Button(item.pinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
            Divider()
            Button("Delete") { clipboard.remove(item) }
        }
    }

    @ViewBuilder
    private func transformItems(_ item: ClipboardStore.Item) -> some View {
        let transforms = ClipboardTransform.applicable(to: item.text)
        let isInvalidJSON = ClipboardTransform.looksLikeInvalidJSON(item.text)
        ForEach(transforms) { transform in
            Button(transform.title) { run(transform, on: item) }
        }
        if isInvalidJSON {
            Text("Not valid JSON")
        } else if transforms.isEmpty {
            Text("No transforms available")
        }
    }

    private func run(_ transform: ClipboardTransform, on item: ClipboardStore.Item) {
        switch clipboard.copy(item, transformedBy: transform) {
        case .success:
            status = RowStatus(id: item.id, message: "Copied", isFailure: false)
        case .failure(let failure):
            status = RowStatus(id: item.id, message: failure.message, isFailure: true)
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

