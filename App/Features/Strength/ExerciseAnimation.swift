import SwiftUI

// How-to animations for strength exercises: a side-on mannequin that loops through the movement. Each exercise is a
// few key poses; the figure eases between them and is drawn fresh each frame, so there are no image or video files.
//
// A pose says where the hips and feet are, how the torso leans and how the arms hang; the knees are worked out from
// the hips and feet (two-bone inverse kinematics), so standing, lunging and lying down all come from the same model.
//
// Coordinates are in units of standing height: x forward (the figure faces right), y up, the floor at y = 0.
// Angles are degrees from straight up, positive towards the front: 90 is forward, 180 is down, -90 is back.

struct Pose {
    /// Which way a knee bends: the side it pushes out to.
    enum Bend {
        case forward, back, up, down
        var vector: CGVector {
            switch self {
            case .forward: CGVector(dx: 1, dy: 0)
            case .back: CGVector(dx: -1, dy: 0)
            case .up: CGVector(dx: 0, dy: 1)
            case .down: CGVector(dx: 0, dy: -1)
            }
        }
    }

    var hip: CGPoint
    var torso: Double
    /// The head's direction; nil to follow the torso (lying on the back, it stays on the floor instead).
    var head: Double? = nil
    var nearAnkle: CGPoint
    var farAnkle: CGPoint
    /// Ankle to toe. 90 is flat on the floor.
    var nearFoot: Double = 90
    var farFoot: Double = 90
    var nearBend: Bend = .forward
    var farBend: Bend = .forward
    /// Upper arm and forearm. (176, 170) hangs relaxed at the side.
    var nearArm: (upper: Double, fore: Double) = (176, 170)
    var farArm: (upper: Double, fore: Double) = (176, 170)

    static let ankle = 0.025

    /// Standing tall, feet under the hips.
    static func standing(arms: (Double, Double) = (176, 170)) -> Pose {
        Pose(hip: CGPoint(x: 0, y: 0.5 + ankle), torso: 0, nearAnkle: CGPoint(x: 0, y: ankle),
             farAnkle: CGPoint(x: 0, y: ankle), nearArm: arms, farArm: arms)
    }

    /// Part way from `self` to `other` (0 is self, 1 is other). Knee bends come from `self`.
    func blended(to other: Pose, _ t: Double) -> Pose {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: mix(a.x, b.x), y: mix(a.y, b.y)) }
        var pose = self
        pose.hip = mix(hip, other.hip)
        pose.torso = mix(torso, other.torso)
        pose.head = (head != nil || other.head != nil) ? mix(head ?? torso, other.head ?? other.torso) : nil
        pose.nearAnkle = mix(nearAnkle, other.nearAnkle)
        pose.farAnkle = mix(farAnkle, other.farAnkle)
        pose.nearFoot = mix(nearFoot, other.nearFoot)
        pose.farFoot = mix(farFoot, other.farFoot)
        pose.nearArm = (mix(nearArm.upper, other.nearArm.upper), mix(nearArm.fore, other.nearArm.fore))
        pose.farArm = (mix(farArm.upper, other.farArm.upper), mix(farArm.fore, other.farArm.fore))
        return pose
    }

    // MARK: Joints

    static let thigh = 0.25, shin = 0.25, torsoLength = 0.29, neck = 0.035, headRadius = 0.072
    static let upperArm = 0.15, forearm = 0.14, foot = 0.085

    struct Joints {
        var hip, shoulder, neckTop, head: CGPoint
        var nearKnee, nearAnkle, nearToe, nearElbow, nearWrist: CGPoint
        var farKnee, farAnkle, farToe, farElbow, farWrist: CGPoint
        var all: [CGPoint] {
            [hip, shoulder, neckTop, head, nearKnee, nearAnkle, nearToe, nearElbow, nearWrist,
             farKnee, farAnkle, farToe, farElbow, farWrist]
        }
    }

    static func step(_ from: CGPoint, _ angle: Double, _ length: Double) -> CGPoint {
        let r = angle * .pi / 180
        return CGPoint(x: from.x + length * sin(r), y: from.y + length * cos(r))
    }

    /// Where the knee goes for a hip and an ankle: two equal bones, bending to the `bend` side.
    static func knee(hip: CGPoint, ankle: CGPoint, bend: Bend) -> CGPoint {
        let dx = ankle.x - hip.x, dy = ankle.y - hip.y
        let full = max(hypot(dx, dy), 0.0001)
        let reach = min(full, thigh + shin - 0.0001)
        let ux = dx / full, uy = dy / full
        let mid = CGPoint(x: hip.x + ux * reach / 2, y: hip.y + uy * reach / 2)
        let height = sqrt(max(thigh * thigh - reach * reach / 4, 0))
        let side = bend.vector
        let (px, py) = (-uy * side.dx + ux * side.dy) >= 0 ? (-uy, ux) : (uy, -ux)
        return CGPoint(x: mid.x + px * height, y: mid.y + py * height)
    }

    var joints: Joints {
        let shoulder = Self.step(hip, torso, Self.torsoLength)
        let headAngle = head ?? torso
        let neckTop = Self.step(shoulder, headAngle, Self.neck)
        let headCentre = Self.step(neckTop, headAngle, Self.headRadius * 0.9)
        let nearElbow = Self.step(shoulder, nearArm.upper, Self.upperArm)
        let farElbow = Self.step(shoulder, farArm.upper, Self.upperArm)
        return Joints(hip: hip, shoulder: shoulder, neckTop: neckTop, head: headCentre,
                      nearKnee: Self.knee(hip: hip, ankle: nearAnkle, bend: nearBend), nearAnkle: nearAnkle,
                      nearToe: Self.step(nearAnkle, nearFoot, Self.foot), nearElbow: nearElbow,
                      nearWrist: Self.step(nearElbow, nearArm.fore, Self.forearm),
                      farKnee: Self.knee(hip: hip, ankle: farAnkle, bend: farBend), farAnkle: farAnkle,
                      farToe: Self.step(farAnkle, farFoot, Self.foot), farElbow: farElbow,
                      farWrist: Self.step(farElbow, farArm.fore, Self.forearm))
    }
}

/// One exercise's movement.
struct ExerciseMotion: Hashable {
    struct Key {
        /// Where in the loop this pose is reached (0…1).
        var at: Double
        var pose: Pose
        /// How hard the working muscles are working here (0…1): how brightly they glow.
        var effort: Double
    }

    /// The muscles that glow as they work.
    enum Muscle { case thighs, calves, core }

    enum Prop {
        /// A step from x0 to x1, this high.
        case step(x0: Double, x1: Double, height: Double)
        /// A wall to hold, at x.
        case wall(x: Double)
    }

    let name: String
    let keys: [Key]
    /// Seconds for one repetition.
    let seconds: Double
    /// The rhythm in words, shown above the figure: "Down 2 s · pause · up 1 s".
    let tempo: String
    let muscle: Muscle
    var props: [Prop] = []

    static func == (a: Self, b: Self) -> Bool { a.name == b.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    /// The pose `progress` (0…1) of the way through a repetition, eased in and out between keys.
    func pose(at progress: Double) -> Pose { blend(at: progress).pose }
    func effort(at progress: Double) -> Double { blend(at: progress).effort }

    private func blend(at progress: Double) -> (pose: Pose, effort: Double) {
        guard let after = keys.firstIndex(where: { $0.at >= progress }), after > 0 else {
            return (keys[0].pose, keys[0].effort)
        }
        let a = keys[after - 1], b = keys[after]
        let t = (progress - a.at) / max(b.at - a.at, .ulpOfOne)
        let eased = t * t * (3 - 2 * t)  // Smoothstep: no jerk at either end.
        return (a.pose.blended(to: b.pose, eased), a.effort + (b.effort - a.effort) * eased)
    }

    /// The hardest moment, for Reduce Motion's still frame.
    var hardestProgress: Double { keys.max { $0.effort < $1.effort }?.at ?? 0.5 }

    /// Which way the work is going at `progress`: harder, easier, or holding.
    func direction(at progress: Double) -> Direction {
        let change = effort(at: min(1, progress + 0.02)) - effort(at: progress)
        return abs(change) < 0.004 ? .hold : (change > 0 ? .into : .outOf)
    }

    enum Direction { case into, outOf, hold }

    /// Everything the figure reaches across the loop, so it can be scaled to fit.
    var bounds: CGRect {
        var points = keys.flatMap { $0.pose.joints.all }
        for prop in props {
            switch prop {
            case .step(let x0, let x1, let height): points += [CGPoint(x: x0, y: height), CGPoint(x: x1, y: 0)]
            case .wall(let x): points += [CGPoint(x: x + 0.03, y: 0.95)]
            }
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        let pad = 0.09
        let minX = (xs.min() ?? 0) - pad, maxX = (xs.max() ?? 1) + pad
        return CGRect(x: minX, y: 0, width: maxX - minX, height: (ys.max() ?? 1) + pad)
    }
}

// MARK: - The exercises

extension ExerciseMotion {
    private static let a = Pose.ankle

    static let squat = ExerciseMotion(name: "squat", keys: {
        let bottom = Pose(hip: CGPoint(x: -0.17, y: 0.29), torso: 34, nearAnkle: CGPoint(x: 0, y: a),
                          farAnkle: CGPoint(x: 0, y: a), nearArm: (92, 92), farArm: (92, 92))
        return [Key(at: 0, pose: .standing(), effort: 0), Key(at: 0.075, pose: .standing(), effort: 0),
                Key(at: 0.575, pose: bottom, effort: 1), Key(at: 0.675, pose: bottom, effort: 1),
                Key(at: 0.925, pose: .standing(), effort: 0), Key(at: 1, pose: .standing(), effort: 0)]
    }(), seconds: 4, tempo: String(localized: "Down 2 s · pause · up 1 s"), muscle: .thighs)

    /// Front leg (near) planted; back leg steps back until both knees are at right angles.
    private static let lungeBottom = Pose(hip: CGPoint(x: -0.2, y: 0.3), torso: 6, nearAnkle: CGPoint(x: 0.04, y: a),
                                          farAnkle: CGPoint(x: -0.56, y: 0.07), farFoot: 135, farBend: .down,
                                          nearArm: (178, 172), farArm: (178, 172))

    static let reverseLunge = ExerciseMotion(name: "reverseLunge", keys: {
        let stepping = Pose(hip: CGPoint(x: -0.08, y: 0.47), torso: 2, nearAnkle: CGPoint(x: 0.02, y: a),
                            farAnkle: CGPoint(x: -0.3, y: 0.12), farFoot: 120, farBend: .down)
        return [Key(at: 0, pose: .standing(), effort: 0), Key(at: 0.06, pose: .standing(), effort: 0),
                Key(at: 0.28, pose: stepping, effort: 0.3), Key(at: 0.55, pose: lungeBottom, effort: 1),
                Key(at: 0.65, pose: lungeBottom, effort: 1), Key(at: 0.82, pose: stepping, effort: 0.3),
                Key(at: 0.96, pose: .standing(), effort: 0), Key(at: 1, pose: .standing(), effort: 0)]
    }(), seconds: 4.5, tempo: String(localized: "Step back · lower · drive up"), muscle: .thighs)

    static let splitSquat = ExerciseMotion(name: "splitSquat", keys: {
        var top = lungeBottom
        top.hip = CGPoint(x: -0.22, y: 0.49)
        top.torso = 4
        return [Key(at: 0, pose: top, effort: 0), Key(at: 0.08, pose: top, effort: 0),
                Key(at: 0.55, pose: lungeBottom, effort: 1), Key(at: 0.65, pose: lungeBottom, effort: 1),
                Key(at: 0.92, pose: top, effort: 0), Key(at: 1, pose: top, effort: 0)]
    }(), seconds: 4, tempo: String(localized: "Down 2 s · up 1 s"), muscle: .thighs)

    /// On the back, head to the left, knees up, arms along the floor.
    private static let bridgeDown = Pose(hip: CGPoint(x: -0.32, y: 0.065), torso: -90, head: -90,
                                         nearAnkle: CGPoint(x: 0, y: a), farAnkle: CGPoint(x: 0, y: a),
                                         nearBend: .up, farBend: .up, nearArm: (90, 90), farArm: (90, 90))
    /// Hips up into a straight line from shoulders to knees; the upper back stays on the floor.
    private static let bridgeUp: Pose = {
        var pose = bridgeDown
        pose.hip = CGPoint(x: -0.29, y: 0.27)
        pose.torso = -135
        return pose
    }()

    private static func bridge(_ name: String, down: Pose, up: Pose) -> ExerciseMotion {
        ExerciseMotion(name: name, keys: [
            Key(at: 0, pose: down, effort: 0), Key(at: 0.08, pose: down, effort: 0),
            Key(at: 0.38, pose: up, effort: 1), Key(at: 0.62, pose: up, effort: 1),
            Key(at: 0.94, pose: down, effort: 0), Key(at: 1, pose: down, effort: 0),
        ], seconds: 4, tempo: String(localized: "Lift · squeeze 1 s · lower slowly"), muscle: .thighs)
    }

    static let gluteBridge = bridge("gluteBridge", down: bridgeDown, up: bridgeUp)

    static let singleLegBridge: ExerciseMotion = {
        var down = bridgeDown, up = bridgeUp
        down.farAnkle = CGPoint(x: 0.01, y: 0.435)
        down.farFoot = 40
        up.farAnkle = CGPoint(x: 0.21, y: 0.274)  // In line with the thigh.
        up.farFoot = 60
        return bridge("singleLegBridge", down: down, up: up)
    }()

    /// On the toes, heels up: the balls of the feet stay put.
    private static let raisedAnkle = CGPoint(x: 0.0154, y: 0.0738)
    private static let wallArms = (62.0, 78.0)

    static let calfRaise = ExerciseMotion(name: "calfRaise", keys: {
        var up = Pose.standing()
        up.hip = CGPoint(x: raisedAnkle.x, y: raisedAnkle.y + 0.5)
        up.nearAnkle = raisedAnkle
        up.farAnkle = raisedAnkle
        up.nearFoot = 125
        up.farFoot = 125
        return [Key(at: 0, pose: .standing(), effort: 0), Key(at: 0.1, pose: .standing(), effort: 0),
                Key(at: 0.35, pose: up, effort: 1), Key(at: 0.45, pose: up, effort: 1),
                Key(at: 0.95, pose: .standing(), effort: 0), Key(at: 1, pose: .standing(), effort: 0)]
    }(), seconds: 3.5, tempo: String(localized: "Up 1 s · down 2 s"), muscle: .calves)

    static let singleLegCalfRaise = ExerciseMotion(name: "singleLegCalfRaise", keys: {
        var down = Pose.standing(arms: wallArms)
        down.farAnkle = CGPoint(x: -0.16, y: 0.2)
        down.farFoot = 150
        var up = down
        up.hip = CGPoint(x: raisedAnkle.x, y: raisedAnkle.y + 0.5)
        up.nearAnkle = raisedAnkle
        up.nearFoot = 125
        up.farAnkle = CGPoint(x: -0.1446, y: 0.2488)
        up.nearArm = (58, 74)
        up.farArm = (58, 74)
        return [Key(at: 0, pose: down, effort: 0), Key(at: 0.1, pose: down, effort: 0),
                Key(at: 0.35, pose: up, effort: 1), Key(at: 0.45, pose: up, effort: 1),
                Key(at: 0.95, pose: down, effort: 0), Key(at: 1, pose: down, effort: 0)]
    }(), seconds: 3.5, tempo: String(localized: "Up 1 s · down 2 s"), muscle: .calves, props: [.wall(x: 0.34)])

    static let singleLegRDL = ExerciseMotion(name: "singleLegRDL", keys: {
        var top = Pose.standing()
        top.farAnkle = CGPoint(x: -0.02, y: 0.06)
        let hinge = Pose(hip: CGPoint(x: -0.06, y: 0.48), torso: 80, nearAnkle: CGPoint(x: 0, y: a),
                         farAnkle: CGPoint(x: -0.552, y: 0.393), farFoot: 200, farBend: .down,
                         nearArm: (180, 180), farArm: (180, 180))
        return [Key(at: 0, pose: top, effort: 0), Key(at: 0.08, pose: top, effort: 0),
                Key(at: 0.55, pose: hinge, effort: 1), Key(at: 0.65, pose: hinge, effort: 1),
                Key(at: 0.92, pose: top, effort: 0), Key(at: 1, pose: top, effort: 0)]
    }(), seconds: 4.5, tempo: String(localized: "Hinge 2 s · stand 1 s"), muscle: .thighs)

    /// Forearm plank: elbows under the shoulders, a straight line to the toes.
    private static let plankHold = Pose(hip: CGPoint(x: -0.288, y: 0.155), torso: 83.1,
                                        nearAnkle: CGPoint(x: -0.784, y: 0.095), farAnkle: CGPoint(x: -0.784, y: 0.095),
                                        nearFoot: 195, farFoot: 195, nearBend: .down, farBend: .down,
                                        nearArm: (180, 90), farArm: (180, 90))

    private static func hold(_ name: String, rest: Pose, hold: Pose, tempo: String) -> ExerciseMotion {
        ExerciseMotion(name: name, keys: [
            Key(at: 0, pose: rest, effort: 0), Key(at: 0.08, pose: rest, effort: 0),
            Key(at: 0.22, pose: hold, effort: 1), Key(at: 0.86, pose: hold, effort: 1),
            Key(at: 1, pose: rest, effort: 0),
        ], seconds: 6, tempo: tempo, muscle: .core)
    }

    static let plank: ExerciseMotion = {
        var knees = plankHold
        knees.hip = CGPoint(x: -0.29, y: 0.13)
        knees.torso = 78.3
        knees.nearAnkle = CGPoint(x: -0.7, y: 0.18)
        knees.farAnkle = CGPoint(x: -0.7, y: 0.18)
        knees.nearFoot = 230
        knees.farFoot = 230
        return hold("plank", rest: knees, hold: plankHold, tempo: String(localized: "Hold · straight line, head to heels"))
    }()

    static let sidePlank: ExerciseMotion = {
        var up = plankHold
        up.farArm = (0, 0)
        up.nearFoot = 200
        up.farFoot = 200
        var down = up
        down.hip = CGPoint(x: -0.288, y: 0.08)
        down.torso = 69.1
        return hold("sidePlank", rest: down, hold: up, tempo: String(localized: "Hips up · hold"))
    }()

    static let deadBug = ExerciseMotion(name: "deadBug", keys: {
        let table = Pose(hip: CGPoint(x: 0, y: 0.065), torso: -90, head: -90,
                         nearAnkle: CGPoint(x: 0.25, y: 0.315), farAnkle: CGPoint(x: 0.25, y: 0.315),
                         nearBend: .up, farBend: .up, nearArm: (-4, -4), farArm: (-4, -4))
        let out = CGPoint(x: 0.4924, y: 0.1518)  // Leg straight out, just off the floor.
        var a = table, b = table
        a.nearArm = (-75, -78)
        a.farAnkle = out
        a.farFoot = 70
        b.farArm = (-75, -78)
        b.nearAnkle = out
        b.nearFoot = 70
        return [Key(at: 0, pose: table, effort: 0.4), Key(at: 0.25, pose: a, effort: 1),
                Key(at: 0.5, pose: table, effort: 0.4), Key(at: 0.75, pose: b, effort: 1),
                Key(at: 1, pose: table, effort: 0.4)]
    }(), seconds: 6, tempo: String(localized: "Slow · lower back stays down"), muscle: .core)

    static let stepUp = ExerciseMotion(name: "stepUp", keys: {
        let start = Pose(hip: CGPoint(x: -0.12, y: 0.505), torso: 12, nearAnkle: CGPoint(x: 0.12, y: 0.185),
                         farAnkle: CGPoint(x: -0.14, y: a))
        let top = Pose(hip: CGPoint(x: 0.13, y: 0.685), torso: 4, nearAnkle: CGPoint(x: 0.13, y: 0.185),
                       farAnkle: CGPoint(x: 0.05, y: 0.28), farFoot: 150)
        return [Key(at: 0, pose: start, effort: 0.2), Key(at: 0.1, pose: start, effort: 0.2),
                Key(at: 0.4, pose: top, effort: 1), Key(at: 0.55, pose: top, effort: 1),
                Key(at: 0.95, pose: start, effort: 0.2), Key(at: 1, pose: start, effort: 0.2)]
    }(), seconds: 4, tempo: String(localized: "Up 1 s · down 2 s"), muscle: .thighs,
         props: [.step(x0: 0.02, x1: 0.4, height: 0.16)])

    static let legSwings = ExerciseMotion(name: "legSwings", keys: {
        @MainActor func swing(_ ankle: CGPoint, _ foot: Double) -> Pose {
            var pose = Pose.standing(arms: wallArms)
            pose.farAnkle = ankle
            pose.farFoot = foot
            return pose
        }
        let front = swing(CGPoint(x: 0.3214, y: 0.142), 110), back = swing(CGPoint(x: -0.3214, y: 0.142), 200)
        let middle = swing(CGPoint(x: 0, y: 0.06), 150)
        return [Key(at: 0, pose: front, effort: 0.3), Key(at: 0.25, pose: middle, effort: 0.3),
                Key(at: 0.5, pose: back, effort: 0.3), Key(at: 0.75, pose: middle, effort: 0.3),
                Key(at: 1, pose: front, effort: 0.3)]
    }(), seconds: 2.4, tempo: String(localized: "Relaxed swings, front and back"), muscle: .thighs,
         props: [.wall(x: 0.34)])
}

// MARK: - Drawing

/// The looping figure, with its tempo above. Under Reduce Motion it holds still at the hardest point.
struct ExerciseAnimation: View {
    let motion: ExerciseMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let progress = reduceMotion ? motion.hardestProgress
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: motion.seconds) / motion.seconds
            // The tempo on its own strip, so it never covers the figure.
            VStack(alignment: .leading, spacing: 0) {
                tempo(reduceMotion ? .hold : motion.direction(at: progress))
                    .padding([.top, .leading], 10)
                Mannequin(motion: motion, pose: motion.pose(at: progress), effort: motion.effort(at: progress))
                    .padding(.top, 4)
                    .padding(.horizontal, 8)
            }
        }
        .background(
            LinearGradient(colors: [StrengthStyle.color.opacity(0.10), Theme.subtle.opacity(0.25)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(motion.tempo))
    }

    /// The rhythm, with an arrow for the way the work is going right now.
    private func tempo(_ direction: ExerciseMotion.Direction) -> some View {
        HStack(spacing: 5) {
            Image(systemName: direction == .into ? "arrow.down" : direction == .outOf ? "arrow.up" : "pause.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(StrengthStyle.color)
                .frame(width: 12)
            Text(motion.tempo).font(.caption2.weight(.medium)).foregroundStyle(Theme.secondaryInk)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.7), in: Capsule())
    }
}

/// A smooth, side-on figure: tapered limbs, the far arm and leg in shadow behind, a soft shadow on the floor, props,
/// and the working muscles glowing in the strength colour as the effort builds.
private struct Mannequin: View {
    let motion: ExerciseMotion
    let pose: Pose
    let effort: Double

    var body: some View {
        Canvas { context, size in
            let bounds = motion.bounds
            let unit = min(size.width / bounds.width, size.height / bounds.height)
            let originX = (size.width - bounds.width * unit) / 2 - bounds.minX * unit
            let floorY = size.height - unit * 0.035
            func p(_ point: CGPoint) -> CGPoint { CGPoint(x: originX + point.x * unit, y: floorY - point.y * unit) }
            let j = pose.joints

            /// A limb: a rounded, tapered capsule from `a` (radius `ra`) to `b` (radius `rb`), drawn as one outline
            /// (separate end circles would cancel out where they overlap and leave pale crescents).
            func limb(_ a: CGPoint, _ b: CGPoint, _ ra: Double, _ rb: Double, shift: CGSize = .zero) -> Path {
                let a = CGPoint(x: p(a).x + shift.width, y: p(a).y + shift.height)
                let b = CGPoint(x: p(b).x + shift.width, y: p(b).y + shift.height)
                let normal = atan2(b.x - a.x, -(b.y - a.y))
                let r1 = unit * ra, r2 = unit * rb, steps = 10
                var path = Path()
                for k in 0...steps {
                    let angle = normal - .pi * Double(k) / Double(steps)
                    let point = CGPoint(x: b.x + r2 * cos(angle), y: b.y + r2 * sin(angle))
                    k == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                for k in 0...steps {
                    let angle = normal + .pi - .pi * Double(k) / Double(steps)
                    path.addLine(to: CGPoint(x: a.x + r1 * cos(angle), y: a.y + r1 * sin(angle)))
                }
                path.closeSubpath()
                return path
            }

            // Floor, props and the shadow under the body.
            var floor = Path()
            floor.move(to: CGPoint(x: 4, y: floorY + 1))
            floor.addLine(to: CGPoint(x: size.width - 4, y: floorY + 1))
            context.stroke(floor, with: .color(Theme.subtle), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            let propColour = GraphicsContext.Shading.color(Color(hex: 0xDAD8E2))
            for prop in motion.props {
                switch prop {
                case .step(let x0, let x1, let height):
                    let top = p(CGPoint(x: x0, y: height))
                    context.fill(Path(roundedRect: CGRect(x: top.x, y: top.y, width: (x1 - x0) * unit, height: height * unit),
                                      cornerRadius: unit * 0.015), with: propColour)
                case .wall(let x):
                    let top = p(CGPoint(x: x, y: 0.95))
                    context.fill(Path(roundedRect: CGRect(x: top.x, y: top.y, width: unit * 0.03, height: unit * 0.95),
                                      cornerRadius: unit * 0.01), with: propColour)
                }
            }
            let centreX = (j.hip.x + j.shoulder.x + j.nearAnkle.x + j.farAnkle.x) / 4
            let spread = abs(j.shoulder.x - j.nearAnkle.x) + 0.3
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: unit * 0.025))
                let w = unit * spread, h = unit * 0.05
                layer.fill(Path(ellipseIn: CGRect(x: p(CGPoint(x: centreX, y: 0)).x - w / 2, y: floorY - h * 0.3,
                                                  width: w, height: h)), with: .color(.black.opacity(0.14)))
            }

            let body = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(hex: 0x3A3A44), Theme.ink]),
                startPoint: CGPoint(x: 0, y: p(j.head).y - unit * 0.1), endPoint: CGPoint(x: 0, y: floorY))
            // In shadow: darker than the background, lighter than the near side, so it reads as depth.
            let far = GraphicsContext.Shading.color(Color(hex: 0x76747F))
            let back = CGSize(width: -unit * 0.03, height: -unit * 0.008)

            // Far arm and leg.
            context.fill(limb(j.farAnkle, j.farToe, 0.022, 0.016, shift: back), with: far)
            context.fill(limb(j.farAnkle, j.farKnee, 0.024, 0.032, shift: back), with: far)
            context.fill(limb(j.farKnee, j.hip, 0.032, 0.05, shift: back), with: far)
            context.fill(limb(j.shoulder, j.farElbow, 0.027, 0.022, shift: back), with: far)
            context.fill(limb(j.farElbow, j.farWrist, 0.021, 0.016, shift: back), with: far)

            // Torso, neck and head.
            let torsoShape = limb(j.hip, j.shoulder, 0.056, 0.064)
            context.fill(torsoShape, with: body)
            context.fill(limb(j.shoulder, j.neckTop, 0.026, 0.024), with: body)
            let head = p(j.head), r = unit * Pose.headRadius
            context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)), with: body)

            // Near leg.
            let shinShape = limb(j.nearAnkle, j.nearKnee, 0.026, 0.034)
            let thighShape = limb(j.nearKnee, j.hip, 0.034, 0.054)
            context.fill(limb(j.nearAnkle, j.nearToe, 0.024, 0.017), with: body)
            context.fill(shinShape, with: body)
            context.fill(thighShape, with: body)

            // The working muscles glow as the effort builds.
            let working: Path
            switch motion.muscle {
            case .thighs: working = thighShape
            case .calves: working = shinShape
            case .core: working = torsoShape
            }
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: unit * 0.03 * effort))
                glow.opacity = 0.35 * effort
                glow.fill(working, with: .color(StrengthStyle.color))
            }
            let box = working.boundingRect
            context.fill(working, with: .linearGradient(
                Gradient(colors: [StrengthStyle.color.opacity(0.35 + 0.55 * effort),
                                  Color(hex: 0xC6B9FF).opacity(0.3 + 0.5 * effort)]),
                startPoint: box.origin, endPoint: CGPoint(x: box.maxX, y: box.maxY)))

            // Near arm, in front of everything.
            context.fill(limb(j.shoulder, j.nearElbow, 0.029, 0.024), with: body)
            context.fill(limb(j.nearElbow, j.nearWrist, 0.023, 0.017), with: body)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach([ExerciseMotion.squat, .reverseLunge, .gluteBridge, .plank, .deadBug, .stepUp], id: \.name) { motion in
                ExerciseAnimation(motion: motion).frame(height: 170)
            }
        }
        .padding()
    }
}
