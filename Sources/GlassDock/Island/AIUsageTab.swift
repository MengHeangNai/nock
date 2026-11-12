import SwiftUI

struct AIUsageTab: View {
    @ObservedObject var usage: AIUsageService
    @ObservedObject var settings: DockSettings

    private static let claudeTint = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        HStack(spacing: 12) {
            claudeCard
            codexCard
        }
        .onAppear { usage.start() }
        .onDisappear { usage.stop() }
    }

    private var claudeCard: some View {
        UsageCard(title: "Claude Code", symbol: "asterisk", tint: Self.claudeTint,
                  plan: usage.claudeLimits?.plan, lastActivity: usage.claude?.lastActivity) {
            if let limits = usage.claudeLimits, limits.fiveHour != nil || limits.weekly != nil {
                if let percent = limits.fiveHour {
                    LimitRow(label: "5 hours", percent: percent, resets: limits.fiveHourResets)
                }
                if let percent = limits.weekly {
                    LimitRow(label: "This week", percent: percent, resets: limits.weeklyResets)
                }
            } else {
                TokenSummary(usage: usage.claude, loaded: usage.hasLoaded, toolName: "Claude Code")
                Spacer(minLength: 0)
                if !settings.claudeLimitsEnabled {
                    Button("Show plan limits…") {
                        settings.claudeLimitsEnabled = true
                        usage.refreshClaudeLimits()
                    }
                    .buttonStyle(IslandButtonStyle())
                    .help("Reads Claude Code's sign-in from your Keychain (macOS asks first) and asks Anthropic for your usage.")
                } else if let message = usage.claudeLimitsMessage {
                    Text(message).font(.system(size: 11)).foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var codexCard: some View {
        UsageCard(title: "Codex", symbol: "terminal", tint: .white,
                  plan: usage.codex?.plan, lastActivity: usage.codex?.lastActivity) {
            if let codex = usage.codex, codex.primaryPercent != nil || codex.weeklyPercent != nil {
                if let percent = codex.primaryPercent {
                    LimitRow(label: "5 hours", percent: percent, resets: codex.primaryResets)
                }
                if let percent = codex.weeklyPercent {
                    LimitRow(label: "This week", percent: percent, resets: codex.weeklyResets)
                }
            } else {
                TokenSummary(usage: usage.codex, loaded: usage.hasLoaded, toolName: "Codex")
            }
        }
    }
}

private struct UsageCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let plan: String?
    let lastActivity: Date?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                Text(title).font(.system(size: 15, weight: .semibold))
                if let plan {
                    Text(plan)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                Spacer()
                if let lastActivity {
                    Text(lastActivity, format: .relative(presentation: .named))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LimitRow: View {
    let label: String
    let percent: Double
    let resets: Date?

    var body: some View {
        let high = percent >= 80
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(high ? Color.orange : Color.white)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(high ? Color.orange : Color.white)
                        .frame(width: geometry.size.width * min(max(percent / 100, 0), 1))
                }
            }
            .frame(height: 5)
            if let resets {
                TimelineView(.everyMinute) { context in
                    Text(Self.resetText(resets, now: context.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Resets in 1 hr 19 min" within a day, otherwise "Resets Thu".
    static func resetText(_ date: Date, now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "Resetting now" }
        if seconds < 86_400 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "Resets in " + (hours > 0 ? "\(hours) hr \(minutes) min" : "\(max(minutes, 1)) min")
        }
        return "Resets " + date.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// Token counts from local logs, used when plan limits aren't available.
private struct TokenSummary: View {
    let usage: AIUsageService.ToolUsage?
    let loaded: Bool
    let toolName: String

    var body: some View {
        if let usage {
            VStack(alignment: .leading, spacing: 2) {
                Text(AIUsageService.formatTokens(usage.windowTokens) + " tokens")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(usage.windowResets.map { "This 5-hour window · resets \($0.formatted(date: .omitted, time: .shortened))" }
                     ?? "Today: \(AIUsageService.formatTokens(usage.todayTokens)) tokens · \(usage.todayRequests) requests")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else if !loaded {
            ProgressView().controlSize(.small)
        } else {
            Text("No \(toolName) activity found on this Mac")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
