import SwiftUI

// How-to animations for strength exercises: a side-on stick figure that loops through the movement. Each exercise is
// a few key poses (joint angles); the figure eases between them and is drawn fresh each frame, so there are no image
// or video files, and it's crisp at any size.

/// A body position, seen from the side, facing right. Angles are in degrees from straight up (legs, torso) or
/// straight down (arms); positive leans forward, towards where the figure faces.
struct Pose {
    /// Ankle to knee. Positive: knee forward over the toes.
    var shin: Double = 0
    /// Knee to hip. Negative: hips back behind the knees.
    var thigh: Double = 0
    /// Hip to shoulder. Positive: chest leaning forward.
    var torso: Double = 0
    /// Shoulder to elbow, from hanging straight down. Positive: arm raised forward.
    var upperArm: Double = 4
    /// Elbow to wrist, from hanging straight down.
    var forearm: Double = 10

    static let standing = Pose()

    /// Part way from `self` to `other` (0 is self, 1 is other).
    func blended(to other: Pose, _ t: Double) -> Pose {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return Pose(shin: mix(shin, other.shin), thigh: mix(thigh, other.thigh), torso: mix(torso, other.torso),
                    upperArm: mix(upperArm, other.upperArm), forearm: mix(forearm, other.forearm))
    }
}

/// One exercise's movement: poses in order, each held or moved to over a share of the loop.
struct ExerciseMotion: Hashable {
    struct Key: Hashable {
        /// Where in the loop this pose is reached (0…1).
        var at: Double
        var pose: PoseID
    }

    /// Named so motions can be Hashable (poses are plain numbers).
    enum PoseID: Hashable { case standing, squatBottom }

    let keys: [Key]
    /// Seconds for one repetition.
    let seconds: Double
    /// The rhythm in words, shown under the figure: "Down 2 s · pause · up 1 s".
    let tempo: String
    /// The pose where the work is hardest (fully lit muscles; also what Reduce Motion shows).
    let hardest: PoseID

    static func pose(_ id: PoseID) -> Pose {
        switch id {
        case .standing: .standing
        // Hips back and down until the thighs are about level, knees forward over the toes, chest up and leaning a
        // little, arms out in front for balance.
        case .squatBottom: Pose(shin: 32, thigh: -78, torso: 34, upperArm: 88, forearm: 88)
        }
    }

    /// Stand, sit back and down for 2 seconds, pause, drive up in 1, stand tall. Four seconds a rep.
    static let squat = ExerciseMotion(keys: [
        Key(at: 0, pose: .standing), Key(at: 0.075, pose: .standing),
        Key(at: 0.575, pose: .squatBottom), Key(at: 0.675, pose: .squatBottom),
        Key(at: 0.925, pose: .standing), Key(at: 1, pose: .standing),
    ], seconds: 4, tempo: String(localized: "Down 2 s · pause · up 1 s"), hardest: .squatBottom)

    /// How hard the working muscles are working at `progress`: 0 at rest, 1 at the hardest pose.
    func effort(at progress: Double) -> Double {
        let hard = Self.pose(hardest), rest = Self.pose(keys.first?.pose ?? .standing), now = pose(at: progress)
        let span = abs(hard.thigh - rest.thigh) + abs(hard.torso - rest.torso)
        guard span > 0 else { return 0 }
        return min(1, (abs(now.thigh - rest.thigh) + abs(now.torso - rest.torso)) / span)
    }

    /// Which way the body is moving at `progress`: towards the hard pose, back, or holding.
    func direction(at progress: Double) -> Direction {
        let change = effort(at: min(1, progress + 0.02)) - effort(at: progress)
        return abs(change) < 0.004 ? .hold : (change > 0 ? .into : .outOf)
    }

    enum Direction { case into, outOf, hold }

    /// The pose `progress` (0…1) of the way through a repetition, eased in and out between keys.
    func pose(at progress: Double) -> Pose {
        guard let after = keys.firstIndex(where: { $0.at >= progress }), after > 0 else {
            return Self.pose(keys.first?.pose ?? .standing)
        }
        let a = keys[after - 1], b = keys[after]
        let span = max(b.at - a.at, .ulpOfOne)
        let t = (progress - a.at) / span
        let eased = t * t * (3 - 2 * t)  // Smoothstep: no jerk at either end.
        return Self.pose(a.pose).blended(to: Self.pose(b.pose), eased)
    }
}

/// The looping figure, with its tempo underneath. Under Reduce Motion it holds still at the hardest point.
struct ExerciseAnimation: View {
    let motion: ExerciseMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let progress = reduceMotion ? hardestProgress
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: motion.seconds) / motion.seconds
            // The tempo on its own strip, so it never covers the figure.
            VStack(alignment: .leading, spacing: 0) {
                tempo(reduceMotion ? .hold : motion.direction(at: progress))
                    .padding([.top, .leading], 10)
                Mannequin(pose: motion.pose(at: progress), effort: motion.effort(at: progress))
                    .padding(.top, 4)
            }
        }
        .background(
            LinearGradient(colors: [StrengthStyle.color.opacity(0.10), Theme.subtle.opacity(0.25)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(motion.tempo))
    }

    private var hardestProgress: Double {
        motion.keys.first { $0.pose == motion.hardest }?.at ?? 0.5
    }

    /// The rhythm, with an arrow for the way the body's moving right now.
    private func tempo(_ direction: ExerciseMotion.Direction) -> some View {
        HStack(spacing: 5) {
            Image(systemName: direction == .into ? "arrow.down" : direction == .outOf ? "arrow.up" : "pause.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(StrengthStyle.color)
                .frame(width: 12)
                .contentTransition(.symbolEffect(.replace))
            Text(motion.tempo).font(.caption2.weight(.medium)).foregroundStyle(Theme.secondaryInk)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.7), in: Capsule())
    }
}

/// A smooth, side-on figure: tapered limbs with rounded joints, the far arm and leg in a lighter shade behind, a soft
/// shadow on the floor, and the working muscles glowing in the strength colour as the effort builds.
private struct Mannequin: View {
    let pose: Pose
    /// 0…1: how brightly the working muscles glow.
    let effort: Double

    // Segment lengths as a share of standing height, and limb thickness (radius) at each end.
    private let shin = 0.25, thigh = 0.25, torso = 0.29, neck = 0.035, head = 0.072
    private let upperArm = 0.15, forearm = 0.14, foot = 0.085

    var body: some View {
        Canvas { context, size in
            let unit = size.height / 1.16
            let ankle = CGPoint(x: size.width / 2 + unit * 0.02, y: size.height - unit * 0.1)
            func up(_ start: CGPoint, _ length: Double, _ angle: Double) -> CGPoint {
                let r = angle * .pi / 180
                return CGPoint(x: start.x + unit * length * sin(r), y: start.y - unit * length * cos(r))
            }
            func down(_ start: CGPoint, _ length: Double, _ angle: Double) -> CGPoint {
                let r = angle * .pi / 180
                return CGPoint(x: start.x + unit * length * sin(r), y: start.y + unit * length * cos(r))
            }
            let knee = up(ankle, shin, pose.shin)
            let hip = up(knee, thigh, pose.thigh)
            let shoulder = up(hip, torso, pose.torso)
            let neckTop = up(shoulder, neck, pose.torso * 0.5)
            let headCentre = up(neckTop, head * 0.9, pose.torso * 0.3)
            let elbow = down(shoulder, upperArm, pose.upperArm)
            let wrist = down(elbow, forearm, pose.forearm)
            let toe = CGPoint(x: ankle.x + unit * foot, y: ankle.y + unit * 0.012)

            /// A limb: a rounded, tapered capsule from `a` (radius `ra`) to `b` (radius `rb`), in units, drawn as one
            /// outline (separate end circles would cancel out where they overlap and leave pale crescents).
            func limb(_ a: CGPoint, _ b: CGPoint, _ ra: Double, _ rb: Double) -> Path {
                let dx = b.x - a.x, dy = b.y - a.y
                let normal = atan2(dx, -dy)  // Direction of (-dy, dx): the limb's side.
                let r1 = unit * ra, r2 = unit * rb, steps = 10
                var path = Path()
                // Round the far end, from one side through the tip to the other side…
                for k in 0...steps {
                    let angle = normal - .pi * Double(k) / Double(steps)
                    let point = CGPoint(x: b.x + r2 * cos(angle), y: b.y + r2 * sin(angle))
                    k == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                // …then back round the near end.
                for k in 0...steps {
                    let angle = normal + .pi - .pi * Double(k) / Double(steps)
                    path.addLine(to: CGPoint(x: a.x + r1 * cos(angle), y: a.y + r1 * sin(angle)))
                }
                path.closeSubpath()
                return path
            }

            // The far side sits a touch behind and back, so the near limbs overlap it.
            let back = CGSize(width: -unit * 0.035, height: -unit * 0.006)
            func shifted(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + back.width, y: p.y + back.height) }

            // Shadow on the floor, under the body's weight.
            let centre = (ankle.x + hip.x + shoulder.x) / 3
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: unit * 0.025))
                let w = unit * (0.42 + 0.1 * effort), h = unit * 0.05
                layer.fill(Path(ellipseIn: CGRect(x: centre - w / 2, y: ankle.y + unit * 0.005, width: w, height: h)),
                           with: .color(.black.opacity(0.16)))
            }

            let body = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(hex: 0x3A3A44), Theme.ink]),
                startPoint: CGPoint(x: 0, y: headCentre.y), endPoint: CGPoint(x: 0, y: ankle.y))
            // In shadow, darker than the background but lighter than the near side, so it reads as depth.
            let far = GraphicsContext.Shading.color(Color(hex: 0x76747F))

            // Far arm and leg.
            context.fill(limb(shifted(ankle), shifted(toe), 0.022, 0.016), with: far)
            context.fill(limb(shifted(ankle), shifted(knee), 0.024, 0.032), with: far)
            context.fill(limb(shifted(knee), shifted(hip), 0.032, 0.05), with: far)
            context.fill(limb(shifted(shoulder), shifted(elbow), 0.027, 0.022), with: far)
            context.fill(limb(shifted(elbow), shifted(wrist), 0.021, 0.016), with: far)

            // Body: torso (wider at the chest), neck and head.
            context.fill(limb(hip, shoulder, 0.056, 0.064), with: body)
            context.fill(limb(shoulder, neckTop, 0.026, 0.024), with: body)
            context.fill(Path(ellipseIn: CGRect(x: headCentre.x - unit * head, y: headCentre.y - unit * head,
                                                width: unit * head * 2, height: unit * head * 2)), with: body)

            // Near leg, with the thigh and glute glowing as they work.
            context.fill(limb(ankle, toe, 0.024, 0.017), with: body)
            context.fill(limb(ankle, knee, 0.026, 0.034), with: body)
            let thighShape = limb(knee, hip, 0.034, 0.054)
            context.fill(thighShape, with: body)
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: unit * 0.03 * effort))
                glow.opacity = 0.35 * effort
                glow.fill(thighShape, with: .color(StrengthStyle.color))
            }
            context.fill(thighShape, with: .linearGradient(
                Gradient(colors: [StrengthStyle.color.opacity(0.35 + 0.55 * effort), Color(hex: 0xC6B9FF).opacity(0.3 + 0.5 * effort)]),
                startPoint: knee, endPoint: hip))

            // Near arm, in front of everything.
            context.fill(limb(shoulder, elbow, 0.029, 0.024), with: body)
            context.fill(limb(elbow, wrist, 0.023, 0.017), with: body)
        }
    }
}

#Preview {
    ExerciseAnimation(motion: .squat)
        .frame(width: 280, height: 180)
        .padding()
}
