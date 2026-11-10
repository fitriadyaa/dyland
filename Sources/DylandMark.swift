import SwiftUI

// Only schedule idle frames during the blink, not throughout the 4.8-second pause.
struct MascotSchedule: TimelineSchedule {
    var moving: Bool
    var paused: Bool

    func nextTick(after time: TimeInterval) -> TimeInterval {
        if moving { return time + 1.0 / 20 }
        let phase = time.truncatingRemainder(dividingBy: 4.8)
        if phase < 4.36 { return max(time + 1.0 / 30, time + 4.36 - phase) }
        if phase < 4.64 { return time + 1.0 / 30 }
        return time + 4.8 + 4.36 - phase
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        if paused { return AnySequence([startDate]) }
        return AnySequence(sequence(first: startDate) { date in
            Date(timeIntervalSinceReferenceDate: nextTick(after: date.timeIntervalSinceReferenceDate))
        })
    }
}

// A1 capsule, drawn natively without the concept sheet's background or square canvas.
struct DylandMark: View {
    var kind: String?
    var attentive = false
    var animating = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func eyes(at time: TimeInterval, reducedMotion: Bool) -> (height: CGFloat, x: CGFloat, y: CGFloat) {
        guard !reducedMotion, kind != "paused" else { return (eyeHeight, 0, 0) }
        let phase = time.truncatingRemainder(dividingBy: 4.8)
        let blink = max(0, 1 - abs(phase - 4.5) / 0.14)
        let height = attentive ? max(eyeHeight, 32) : eyeHeight
        let glance = kind == "working" && !attentive ? CGFloat(sin(time * .pi / 3)) * 3 : 0
        return (height + (2 - height) * blink, glance, attentive ? -3 : 0)
    }

    var eyeHeight: CGFloat {
        switch kind {
        case "done", "interrupted", "paused": 5
        case "question", "permission", "error": 32
        default: 30
        }
    }

    var body: some View {
        TimelineView(MascotSchedule(moving: kind == "working" && !attentive, paused: !animating || reduceMotion || kind == "paused")) {
            timeline in
            let eyes = eyes(at: timeline.date.timeIntervalSinceReferenceDate, reducedMotion: reduceMotion || !animating)
            Canvas { context, size in
                context.scaleBy(x: size.width / 116, y: size.height / 77)
                context.translateBy(x: -8, y: -51)
                var body = Path()
                body.move(to: CGPoint(x: 8, y: 89))
                body.addCurve(
                    to: CGPoint(x: 49, y: 51), control1: CGPoint(x: 8, y: 65), control2: CGPoint(x: 25, y: 51)
                )
                body.addLine(to: CGPoint(x: 91, y: 51))
                body.addCurve(
                    to: CGPoint(x: 124, y: 90), control1: CGPoint(x: 112, y: 51),
                    control2: CGPoint(x: 124, y: 67))
                body.addLine(to: CGPoint(x: 124, y: 128))
                body.addLine(to: CGPoint(x: 8, y: 128))
                body.closeSubpath()
                context.fill(body, with: .color(Color(red: 236 / 255, green: 236 / 255, blue: 231 / 255)))
                let ink = Color(red: 69 / 255, green: 75 / 255, blue: 80 / 255)
                var base = Path()
                base.move(to: CGPoint(x: 8, y: 108))
                base.addCurve(
                    to: CGPoint(x: 124, y: 104), control1: CGPoint(x: 36, y: 115),
                    control2: CGPoint(x: 85, y: 116))
                base.addLine(to: CGPoint(x: 124, y: 128))
                base.addLine(to: CGPoint(x: 8, y: 128))
                base.closeSubpath()
                context.clip(to: body)
                context.fill(base, with: .color(ink))
                for x: CGFloat in [41.5, 75.5] {
                    let eye = RoundedRectangle(cornerRadius: min(6, eyes.height / 2))
                        .path(
                            in: CGRect(
                                x: x + eyes.x, y: 80.5 + eyes.y - eyes.height / 2, width: 12, height: eyes.height))
                    context.fill(eye, with: .color(Color(red: 20 / 255, green: 23 / 255, blue: 26 / 255)))
                }
            }
        }
        .aspectRatio(116.0 / 77.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
