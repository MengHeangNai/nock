import SwiftUI

extension View {
    func islandCard(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct IslandMessage: View {
    let text: String
    var systemImage: String?
    var spinner = false

    var body: some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().controlSize(.small) }
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Home

struct HomeDashboard: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var calendar: CalendarService
    @ObservedObject var battery: BatteryMonitor
    let settings: DockSettings
    let pet: NotchPetMonitor
    let state: IslandState

    var body: some View {
        HStack(spacing: 20) {
            HomeNowPlaying(nowPlaying: nowPlaying, settings: settings, pet: pet, state: state)
                .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    WeekStrip(calendar: calendar)
                    if battery.level != nil {
                        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 44)
                        BatteryBadge(battery: battery)
                            .onTapGesture { state.tab = .battery }
                    }
                }
                NextEventCard(calendar: calendar)
                    .onTapGesture(count: 2) { state.tab = .upNext }
            }
            .frame(width: 430)
        }
    }
}

private struct HomeNowPlaying: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var settings: DockSettings
    @ObservedObject var pet: NotchPetMonitor
    let state: IslandState

    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(nowPlaying: nowPlaying, size: 92)
                .shadow(color: nowPlaying.artwork == nil ? .clear : nowPlaying.accentColor.opacity(0.45), radius: 22)
                .onTapGesture {
                    if nowPlaying.player == nil { nowPlaying.openPlayer() } else { state.tab = .nowPlaying }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(nowPlaying.title ?? "Not Playing")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(nowPlaying.artist ?? "Apple Music or Spotify")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if nowPlaying.player != nil {
                    PlaybackProgress(nowPlaying: nowPlaying, showsTimes: false)
                        .padding(.top, 8)
                }
                HStack(spacing: 26) {
                    control("backward.fill", size: 15, action: nowPlaying.previous)
                    control(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 22, action: nowPlaying.playPause)
                    control("forward.fill", size: 15, action: nowPlaying.next)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if settings.showNotchPet && nowPlaying.isPlaying {
                        NotchPetView(mood: pet.mood, stage: pet.stage, size: 28)
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLabel(playbackControlName(symbol), edge: .top)
    }
}

private struct WeekStrip: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                ForEach(calendar.weekDays, id: \.self) { day in
                    let isToday = Calendar.current.isDate(day, inSameDayAs: context.date)
                    VStack(spacing: 5) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                            .textCase(.uppercase)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isToday ? Color.white : Color.secondary)
                        Text(day, format: .dateTime.day())
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(width: 30, height: 30)
                            .background(isToday ? Color.blue : Color.clear, in: Circle())
                        HStack(spacing: 2) {
                            ForEach(Array(calendar.colors(on: day).enumerated()), id: \.offset) { _, color in
                                Circle().fill(color).frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct BatteryBadge: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        let level = battery.level ?? 0
        let color: Color = battery.isPluggedIn ? .green : (level <= 20 ? .red : .white)
        VStack(spacing: 4) {
            Image(systemName: battery.isPluggedIn ? "battery.100percent.bolt" : BatteryMonitor.symbol(for: level))
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
            Text("\(level)%")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .frame(width: 56)
    }
}

struct NextEventCard: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        Group {
            switch calendar.access {
            case .notDetermined:
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                    Text("See your next meeting here").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Connect Calendar") { calendar.requestAccess() }
                        .buttonStyle(IslandButtonStyle())
                }
            case .denied:
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                    Text("Calendar access is off").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") { calendar.openPrivacySettings() }
                        .buttonStyle(IslandButtonStyle())
                }
            case .granted:
                if let event = calendar.upcoming.first {
                    EventRow(event: event)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                        Text("No upcoming events").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EventRow: View {
    let event: CalendarService.Event

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 10) {
                Capsule().fill(event.color).frame(width: 4, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(Self.when(event, now: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let url = event.meetingURL {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("Join", systemImage: "video.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    static func when(_ event: CalendarService.Event, now: Date) -> String {
        let time = event.start.formatted(date: .omitted, time: .shortened)
        if event.start <= now {
            return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))"
        }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return "In \(max(minutes, 1)) min · \(time)" }
        let calendar = Calendar.current
        if calendar.isDateInToday(event.start) { return "In \(minutes / 60)h \(minutes % 60)m · \(time)" }
        if calendar.isDateInTomorrow(event.start) { return "Tomorrow · \(time)" }
        return event.start.formatted(.dateTime.weekday(.wide)) + " · \(time)"
    }
}

// MARK: - Up Next

struct UpNextTab: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        if calendar.access != .granted {
            NextEventCard(calendar: calendar)
                .frame(maxHeight: .infinity)
        } else if calendar.upcoming.isEmpty {
            IslandMessage(text: "Nothing on your calendar for the next two days", systemImage: "calendar")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(calendar.upcoming.prefix(12)) { event in
                        EventRow(event: event)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - Battery

struct BatteryTab: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        if let level = battery.level {
            let color: Color = battery.isPluggedIn ? .green : (level <= 20 ? .red : .white)
            HStack(spacing: 28) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: Double(level) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        if battery.isPluggedIn {
                            Image(systemName: "bolt.fill").font(.system(size: 14)).foregroundStyle(.green)
                        }
                        Text("\(level)%")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 9) {
                    row("Status", status(level: level))
                    if let time = timeText { row(time.label, time.value) }
                    if let health = battery.healthPercent {
                        row("Health", "\(health)%" + (battery.cycleCount.map { " · \($0) cycles" } ?? ""))
                    }
                    row("Low Power Mode", battery.lowPowerMode ? "On" : "Off")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            IslandMessage(text: "This Mac doesn't have a battery", systemImage: "powerplug")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 13))
    }

    private func status(level: Int) -> String {
        if battery.isCharging { return "Charging" }
        if battery.isPluggedIn { return level >= 99 ? "Fully charged" : "Plugged in, not charging" }
        return "On battery"
    }

    private var timeText: (label: String, value: String)? {
        if battery.isCharging {
            return ("Until full", battery.minutesToFull.map(Self.duration) ?? "Calculating…")
        }
        if !battery.isPluggedIn {
            return ("Remaining", battery.minutesRemaining.map(Self.duration) ?? "Calculating…")
        }
        return nil
    }

    private static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min"
    }
}
