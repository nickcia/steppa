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

    static func pose(_ id: PoseID) -> Pose {
        switch id {
        case .standing: .standing
        // Hips back and down until the thighs are about level, knees forward over the toes, chest up and leaning a
        // little, arms out in front for balance.
        case .squatBottom: Pose(shin: 32, thigh: -78, torso: 34, upperArm: 88, forearm: 88)
        }
    }

    /// Stand, sit back and down (a little slower), pause at the bottom, drive back up, pause at the top.
    static let squat = ExerciseMotion(keys: [
        Key(at: 0, pose: .standing), Key(at: 0.12, pose: .standing),
        Key(at: 0.50, pose: .squatBottom), Key(at: 0.62, pose: .squatBottom),
        Key(at: 0.92, pose: .standing), Key(at: 1, pose: .standing),
    ], seconds: 2.8)

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

/// The looping figure. Under Reduce Motion it holds still at the hardest point of the movement.
struct ExerciseAnimation: View {
    let motion: ExerciseMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let progress = reduceMotion ? 0.55
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: motion.seconds) / motion.seconds
            StickFigure(pose: motion.pose(at: progress))
        }
        .accessibilityHidden(true)
    }
}

/// Draws one pose: ground, leg, torso, head and arm, scaled to fit.
private struct StickFigure: View {
    let pose: Pose

    // Segment lengths as a share of standing height.
    private let shin = 0.25, thigh = 0.25, torso = 0.29, neck = 0.05, head = 0.065
    private let upperArm = 0.15, forearm = 0.14, foot = 0.09

    var body: some View {
        Canvas { context, size in
            let unit = size.height / 1.12
            let ankle = CGPoint(x: size.width / 2 - unit * 0.02, y: size.height - unit * 0.06)
            func point(from start: CGPoint, length: Double, degreesFromUp angle: Double) -> CGPoint {
                let radians = angle * .pi / 180
                return CGPoint(x: start.x + unit * length * sin(radians), y: start.y - unit * length * cos(radians))
            }
            func point(from start: CGPoint, length: Double, degreesFromDown angle: Double) -> CGPoint {
                let radians = angle * .pi / 180
                return CGPoint(x: start.x + unit * length * sin(radians), y: start.y + unit * length * cos(radians))
            }
            let knee = point(from: ankle, length: shin, degreesFromUp: pose.shin)
            let hip = point(from: knee, length: thigh, degreesFromUp: pose.thigh)
            let shoulder = point(from: hip, length: torso, degreesFromUp: pose.torso)
            let headCentre = point(from: shoulder, length: neck + head, degreesFromUp: pose.torso * 0.6)
            let elbow = point(from: shoulder, length: upperArm, degreesFromDown: pose.upperArm)
            let wrist = point(from: elbow, length: forearm, degreesFromDown: pose.forearm)
            let toe = CGPoint(x: ankle.x + unit * foot, y: ankle.y)

            let width = unit * 0.045
            let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            func line(_ points: [CGPoint], _ colour: Color) {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(colour), style: style)
            }

            // Ground.
            var ground = Path()
            ground.move(to: CGPoint(x: size.width * 0.15, y: ankle.y + width / 2 + 2))
            ground.addLine(to: CGPoint(x: size.width * 0.85, y: ankle.y + width / 2 + 2))
            context.stroke(ground, with: .color(Theme.subtle), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Body in ink; the working legs in the strength colour.
            line([toe, ankle, knee, hip], StrengthStyle.color)
            line([hip, shoulder], Theme.ink)
            line([shoulder, elbow, wrist], Theme.ink.opacity(0.75))
            let headRect = CGRect(x: headCentre.x - unit * head, y: headCentre.y - unit * head,
                                  width: unit * head * 2, height: unit * head * 2)
            context.fill(Path(ellipseIn: headRect), with: .color(Theme.ink))
        }
    }
}

#Preview {
    ExerciseAnimation(motion: .squat)
        .frame(width: 160, height: 160)
        .padding()
}
