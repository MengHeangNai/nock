import SwiftUI

private enum AgentActivityStyle {
    static let labelSize: CGFloat = 12
    static let detailSize: CGFloat = 11
    static let statusFont = NSFont.systemFont(ofSize: labelSize, weight: .semibold)
    static let lineCountFont = NSFont.rounded(ofSize: labelSize, weight: .semibold)
    static let badgeFont = NSFont.rounded(ofSize: detailSize, weight: .bold)
    static let gap: CGFloat = 6
    static let rowGap: CGFloat = 2
    static let badgeInset: CGFloat = 5
    static let badgeOpacity = 0.18
    static let secondary = Color.white.opacity(0.62)
    static let waiting = Color.orange
    static let done = Color.green
    static let added = Color.green
    static let removed = Color(red: 1, green: 0.4, blue: 0.36)
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

extension CodingAgent {
    var tint: Color {
        switch self {
        case .claude: return AgentActivityStyle.claude
        case .codex: return .white
        }
    }
}

private struct AgentGlyph: View {
    let session: AgentSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: session.phase == .done ? "checkmark.circle.fill" : session.agent.symbol)
            .font(.system(size: AgentActivityStyle.labelSize, weight: .bold))
            .foregroundStyle(session.phase == .done ? AgentActivityStyle.done : session.agent.tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating, isActive: session.isWaiting && !reduceMotion)
    }
}

private struct AgentLineCounts: View {
    let session: AgentSession

    var body: some View {
        if session.hasLineChanges {
            HStack(spacing: AgentActivityStyle.gap / 2) {
                Text(Self.added(session)).foregroundStyle(AgentActivityStyle.added)
                Text(Self.removed(session)).foregroundStyle(AgentActivityStyle.removed)
            }
            .font(Font(AgentActivityStyle.lineCountFont))
            .monospacedDigit()
            .contentTransition(.numericText())
        }
    }

    static func added(_ session: AgentSession) -> String { "+\(session.linesAdded)" }
    static func removed(_ session: AgentSession) -> String { "−\(session.linesRemoved)" }

    static func width(of session: AgentSession) -> CGFloat {
        guard session.hasLineChanges else { return 0 }
        let font = AgentActivityStyle.lineCountFont
        return font.lineWidth(of: added(session)) + AgentActivityStyle.gap / 2 + font.lineWidth(of: removed(session))
    }
}

struct AgentStatusWing: View {
    let session: AgentSession
    let count: Int
    var isCompact = false

    static func contentWidth(of session: AgentSession) -> CGFloat {
        IslandMetrics.wingGlyphWidth + AgentActivityStyle.gap + AgentActivityStyle.statusFont.lineWidth(of: session.status)
    }

    var body: some View {
        HStack(spacing: AgentActivityStyle.gap) {
            AgentGlyph(session: session)
                .frame(width: IslandMetrics.wingGlyphWidth)
            if !isCompact {
                Text(session.status)
                    .font(Font(AgentActivityStyle.statusFont))
                    .foregroundStyle(session.isWaiting ? AgentActivityStyle.waiting : .white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.accessibilityLabel + (count > 1 ? ", \(count) sessions active" : ""))
    }
}

struct AgentLinesWing: View {
    let session: AgentSession
    let count: Int

    static func contentWidth(of session: AgentSession, count: Int) -> CGFloat {
        let lines = AgentLineCounts.width(of: session)
        guard count > 1 else { return lines }
        let badge = AgentActivityStyle.badgeFont.lineWidth(of: "\(count)") + AgentActivityStyle.badgeInset * 2
        return lines > 0 ? lines + AgentActivityStyle.gap + badge : badge
    }

    var body: some View {
        HStack(spacing: AgentActivityStyle.gap) {
            AgentLineCounts(session: session)
            if count > 1 {
                Text("\(count)")
                    .font(Font(AgentActivityStyle.badgeFont))
                    .monospacedDigit()
                    .padding(.horizontal, AgentActivityStyle.badgeInset)
                    .background(Color.white.opacity(AgentActivityStyle.badgeOpacity), in: Capsule())
            }
        }
        .accessibilityHidden(true)
    }
}

struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: AgentActivityStyle.gap * 1.5) {
            AgentGlyph(session: session)
            VStack(alignment: .leading, spacing: AgentActivityStyle.rowGap) {
                Text(session.project.isEmpty ? session.agent.title : session.project)
                    .font(.system(size: AgentActivityStyle.labelSize + 1, weight: .medium))
                Text(session.status)
                    .font(.system(size: AgentActivityStyle.detailSize))
                    .foregroundStyle(session.isWaiting ? AgentActivityStyle.waiting : AgentActivityStyle.secondary)
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            AgentLineCounts(session: session)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.accessibilityLabel)
    }
}
