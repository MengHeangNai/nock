import SwiftUI

private enum PetStyle {
    static let canvas: CGFloat = 40
    static let bodyTop = Color(red: 0.62, green: 0.90, blue: 0.82)
    static let bodyBottom = Color(red: 0.50, green: 0.82, blue: 0.74)
    static let ear = Color(red: 0.46, green: 0.78, blue: 0.70)
    static let ink = Color(red: 0.10, green: 0.16, blue: 0.19)
    static let cheek = Color(red: 1.0, green: 0.62, blue: 0.68).opacity(0.55)
    static let sleepMark = Color.white.opacity(0.8)
}

private extension PetMood {
    var frameInterval: TimeInterval {
        switch self {
        case .idle: return 1.0 / 8
        case .sleeping, .tired: return 1.0 / 6
        case .dancing, .happy: return 1.0 / 20
        }
    }
}

private extension PetStage {
    var scale: CGFloat {
        switch self {
        case .baby: return 0.78
        case .young: return 0.9
        case .grown: return 1
        }
    }

    var hasEars: Bool { self != .baby }
    var hasTuft: Bool { self == .grown }
}

private enum PetEyes {
    case open(CGFloat)
    case happy
}

private struct PetPose {
    var offsetY: CGFloat = 0
    var squash: CGFloat = 1
    var tilt: Double = 0
    var earTilt: Double = 0
    var eyes = PetEyes.open(1)
    var smile: CGFloat = 1
    var opensMouth = false
    var sleepPhase: Double?

    init(mood: PetMood, time: TimeInterval) {
        switch mood {
        case .idle:
            offsetY = CGFloat(sin(time * 2)) * 0.8
            earTilt = sin(time * 1.5) * 4
            let blinkPhase = time.truncatingRemainder(dividingBy: 4.2)
            eyes = .open(blinkPhase < 0.2 ? 0.1 : 1)
        case .sleeping:
            squash = 1 + CGFloat(sin(time * 1.4)) * 0.03
            eyes = .open(0)
            smile = 0.3
            sleepPhase = (time / 2.4).truncatingRemainder(dividingBy: 1)
        case .dancing:
            let beat = sin(time * 5.5)
            offsetY = -abs(CGFloat(beat)) * 4.5
            squash = 1 - 0.08 * (1 - abs(CGFloat(beat)))
            tilt = cos(time * 2.75) * 10
            earTilt = beat * 14
            opensMouth = true
        case .tired:
            offsetY = 1.5 + CGFloat(sin(time * 1.2)) * 0.6
            squash = 0.94
            tilt = -4
            earTilt = -12
            eyes = .open(0.4)
            smile = -0.3
        case .happy:
            let hop = sin(time * 7)
            offsetY = -abs(CGFloat(hop)) * 5
            squash = 1 - 0.08 * (1 - abs(CGFloat(hop)))
            earTilt = hop * 12
            eyes = .happy
            opensMouth = true
        }
    }
}

struct NotchPetView: View {
    let mood: PetMood
    let stage: PetStage
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: mood.frameInterval, paused: reduceMotion)) { timeline in
            PetFigure(stage: stage, pose: PetPose(mood: mood, time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate))
        }
        .frame(width: PetStyle.canvas, height: PetStyle.canvas)
        .scaleEffect(size / PetStyle.canvas)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mood.accessibilityLabel)
    }
}

private struct PetFigure: View {
    let stage: PetStage
    let pose: PetPose

    var body: some View {
        ZStack {
            if stage.hasEars {
                ear.offset(x: -9, y: -7).rotationEffect(.degrees(-pose.earTilt - 12))
                ear.offset(x: 9, y: -7).rotationEffect(.degrees(pose.earTilt + 12))
            }
            if stage.hasTuft {
                Capsule()
                    .fill(PetStyle.ear)
                    .frame(width: 3, height: 8)
                    .offset(y: -15)
                    .rotationEffect(.degrees(pose.earTilt * 0.5), anchor: .bottom)
            }
            Ellipse()
                .fill(LinearGradient(colors: [PetStyle.bodyTop, PetStyle.bodyBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 26)
                .offset(y: 3)
            face.offset(y: 4)
            if let phase = pose.sleepPhase {
                Text("z")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(PetStyle.sleepMark)
                    .opacity(1 - phase)
                    .offset(x: 14, y: -13 - phase * 6)
            }
        }
        .frame(width: PetStyle.canvas, height: PetStyle.canvas)
        .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
        .scaleEffect(x: 1 / pose.squash, y: pose.squash, anchor: .bottom)
        .offset(y: pose.offsetY)
        .scaleEffect(stage.scale, anchor: .bottom)
    }

    private var ear: some View {
        Circle().fill(PetStyle.ear).frame(width: 9, height: 9)
    }

    private var face: some View {
        ZStack {
            HStack(spacing: 10) {
                eye
                eye
            }
            .offset(y: -3)
            HStack(spacing: 17) {
                Circle().fill(PetStyle.cheek).frame(width: 4.5, height: 4.5)
                Circle().fill(PetStyle.cheek).frame(width: 4.5, height: 4.5)
            }
            .offset(y: 2)
            mouth.offset(y: 4)
        }
    }

    @ViewBuilder
    private var eye: some View {
        switch pose.eyes {
        case .open(let amount):
            Capsule().fill(PetStyle.ink).frame(width: 4, height: max(1.5, 6 * amount))
        case .happy:
            PetSmile(curve: -1)
                .stroke(PetStyle.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 5, height: 3)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        if pose.opensMouth {
            Ellipse().fill(PetStyle.ink).frame(width: 5, height: 4)
        } else {
            PetSmile(curve: pose.smile)
                .stroke(PetStyle.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 7, height: 2)
        }
    }
}

private struct PetSmile: Shape {
    var curve: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.minY + 2 * curve * rect.height))
        return path
    }
}
