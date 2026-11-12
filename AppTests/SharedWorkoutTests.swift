import Foundation
import Testing
import PlanEngine
@testable import TrackStar

/// Sharing a workout with a friend: the file it travels as, reading files from other app versions, and putting the
/// workout on a day of the friend's plan.
@MainActor
struct SharedWorkoutTests {
    let template = WorkoutTemplate(name: "Saturday tempo", blocks: [
        .preset(.warmup),
        WorkoutBlock(role: .repeats, main: BlockPart(effort: .threshold, length: .distance(meters: 1_600)), repeats: 3,
                     recovery: BlockPart(effort: .recovery, length: .time(seconds: 90))),
        WorkoutBlock(role: .run, main: BlockPart(effort: .racePace, length: .distance(meters: 2_000),
                                                 customPace: PaceRange(fast: 290, slow: 300))),
        .preset(.open),
        .preset(.cooldown),
    ])
    let senderPaces = PaceTable(score: 55, goal: .tenK)
    let friendPaces = PaceTable(score: 42, goal: .halfMarathon)

    private func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    private func part(_ shared: SharedWorkout, _ block: Int) -> SharedWorkout.Part { shared.blocks[block].main }

    // MARK: Encoding and decoding

    @Test func roundTripsThroughAFile() throws {
        let shared = SharedWorkout(template: template, paces: senderPaces)
        let decoded = try SharedWorkout.decode(try shared.encoded())
        #expect(decoded == shared)
        #expect(decoded.version == SharedWorkout.currentVersion)
        #expect(decoded.blocks.map(\.role) == ["warmup", "repeats", "run", "run", "cooldown"])
        #expect(decoded.blocks[1].repeats == 3)
        #expect(decoded.blocks[1].recovery?.seconds == 90)
        // The sender's paces travel with it: zone paces from their fitness, and their own pace where they set one.
        #expect(part(decoded, 1).pace == senderPaces.threshold)
        #expect(part(decoded, 2).pace == PaceRange(fast: 290, slow: 300))
        #expect(part(decoded, 3).pace == nil)
    }

    @Test func atMyPacesEachZoneFollowsTheFriendsFitness() throws {
        let shared = try SharedWorkout.decode(try SharedWorkout(template: template, paces: senderPaces).encoded())
        let mine = shared.template(paces: .mine)
        #expect(mine.name == "Saturday tempo")
        #expect(mine.blocks.map(\.main.effort) == template.blocks.map(\.main.effort))
        #expect(mine.blocks.allSatisfy { $0.main.customPace == nil && ($0.recovery?.customPace == nil) })
        #expect(mine.blocks[1].main.pace(friendPaces) == friendPaces.threshold)
        #expect(mine.blocks[1].repeats == 3)
        // A new workout of their own, not a copy of the sender's ID.
        #expect(mine.id != template.id)
    }

    @Test func atTheirPacesTheFriendRunsTheSendersExactPaces() throws {
        let shared = SharedWorkout(template: template, paces: senderPaces)
        let theirs = shared.template(paces: .theirs)
        #expect(theirs.blocks[1].main.pace(friendPaces) == senderPaces.threshold)
        #expect(theirs.blocks[1].recovery?.pace(friendPaces) == Effort.recovery.pace(senderPaces))
        #expect(theirs.blocks[2].main.pace(friendPaces) == PaceRange(fast: 290, slow: 300))
        // "No target" stays by feel.
        #expect(theirs.blocks[3].main.pace(friendPaces) == nil)
        // Same paces, same session: the times match the sender's.
        let sent = template.workout(on: AppModelTests.start, id: "a", paces: senderPaces)
        let received = theirs.workout(on: AppModelTests.start, id: "b", paces: friendPaces)
        #expect(abs(sent.totalSeconds - received.totalSeconds) < 60)
    }

    @Test func plannedWorkoutsShareTheirShape() throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let intervals = try #require(plan.workouts.first { $0.kind == .intervals })
        let shared = try #require(SharedWorkout(workout: intervals, template: nil, paces: plan.paces))
        #expect(shared.name == intervals.name)
        let rebuilt = shared.template(paces: .theirs).workout(on: intervals.date, id: "x", paces: plan.paces)
        #expect(rebuilt.blocks.map(\.iterations) == intervals.blocks.map(\.iterations))
        #expect(rebuilt.blocks.map { $0.steps.map(\.purpose) } == intervals.blocks.map { $0.steps.map(\.purpose) })
        #expect(rebuilt.expandedSteps.map(\.goal) == intervals.expandedSteps.map(\.goal))
        #expect(rebuilt.expandedSteps.map(\.target?.range) == intervals.expandedSteps.map(\.target?.range))
        #expect(abs(rebuilt.totalMeters - intervals.totalMeters) < 1)
    }

    @Test func raceDayIsNotShareable() throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let race = try #require(plan.workouts.first { $0.kind == .race })
        #expect(SharedWorkout(workout: race, template: nil, paces: plan.paces) == nil)
    }

    @Test func fileNamesAreSafe() {
        var shared = SharedWorkout(template: template, paces: senderPaces)
        shared.name = "5 × 1k / hills: \"fast\""
        #expect(shared.fileName == "5 × 1k - hills- -fast-.trackstar")
        shared.name = "  "
        #expect(shared.fileName == "Workout.trackstar")
    }

    // MARK: Other versions and damaged files

    @Test func aFileFromANewerAppThatNeedsItIsTurnedAway() throws {
        var shared = SharedWorkout(template: template, paces: senderPaces)
        shared.version = 7
        shared.minimumVersion = 5
        #expect(throws: SharedWorkout.Problem.newerVersion) { try SharedWorkout.decode(try shared.encoded()) }
        // Even when the rest of it is something this app can't make sense of.
        let strange = try json(["format": "trackstar.workout", "version": 9, "minimumVersion": 9, "steps": "?"])
        #expect(throws: SharedWorkout.Problem.newerVersion) { try SharedWorkout.decode(strange) }
    }

    @Test func aNewerFileOlderAppsCanReadStillOpens() throws {
        let data = try json([
            "format": "trackstar.workout", "version": 3, "minimumVersion": 1, "name": "Hill mix", "fuel": "gel at 30 min",
            "blocks": [
                ["role": "warmup", "repeats": 1, "main": ["effort": "easy", "seconds": 600]],
                ["role": "hillSprint", "repeats": 1,
                 "main": ["effort": "hillSprint", "seconds": 30, "pace": ["fast": 200, "slow": 210]]],
                ["role": "repeats", "repeats": 4, "main": ["effort": "zone6", "meters": 200],
                 "recovery": ["effort": "recovery", "seconds": 60]],
            ],
        ])
        let shared = try SharedWorkout.decode(data)
        let mine = shared.template(paces: .mine)
        #expect(mine.blocks.map(\.role) == [.warmup, .run, .repeats])
        // An effort this app doesn't know keeps the sender's pace, or else runs by feel.
        #expect(mine.blocks[1].main.customPace == PaceRange(fast: 200, slow: 210))
        #expect(mine.blocks[2].main.effort == .open)
        #expect(mine.blocks[2].repeats == 4)
    }

    @Test func olderFilesWithoutOptionalFieldsOpen() throws {
        let data = try json(["format": "trackstar.workout", "version": 1, "name": "Easy",
                             "blocks": [["role": "run", "repeats": 1, "main": ["effort": "easy", "meters": 5000]]]])
        let shared = try SharedWorkout.decode(data)
        #expect(shared.minimumVersion == 1)
        #expect(shared.template(paces: .theirs).blocks.first?.main == BlockPart(effort: .easy, length: .distance(meters: 5000)))
    }

    @Test(arguments: [
        Data(),
        Data("not json".utf8),
        Data("{\"format\":\"trackstar.workout\",\"vers".utf8),
        Data("{\"format\":\"something.else\",\"version\":1,\"name\":\"x\",\"blocks\":[]}".utf8),
        Data(repeating: 0xFF, count: 300),
    ])
    func damagedFilesAreTurnedAway(data: Data) {
        #expect(throws: SharedWorkout.Problem.unreadable) { try SharedWorkout.decode(data) }
    }

    @Test func nonsenseWorkoutsAreTurnedAway() throws {
        func blocks(_ main: [String: Any], repeats: Int = 1) throws -> Data {
            try json(["format": "trackstar.workout", "version": 1, "name": "x",
                      "blocks": [["role": "run", "repeats": repeats, "main": main]]])
        }
        let bad = [
            try json(["format": "trackstar.workout", "version": 1, "name": "x", "blocks": [Any]()]),
            try blocks(["effort": "easy", "meters": -400]),
            try blocks(["effort": "easy"]),
            try blocks(["effort": "easy", "meters": 400, "seconds": 60]),
            try blocks(["effort": "easy", "seconds": 1e9]),
            try blocks(["effort": "easy", "meters": 400], repeats: 10_000),
            try blocks(["effort": "easy", "meters": 400, "pace": ["fast": 300, "slow": 200]]),
            Data(count: SharedWorkout.maxBytes + 1),
        ]
        for data in bad {
            #expect(throws: SharedWorkout.Problem.unreadable) { try SharedWorkout.decode(data) }
        }
    }

    @Test func blankNamesGetOne() throws {
        let data = try json(["format": "trackstar.workout", "version": 1, "name": "   ",
                             "blocks": [["role": "run", "repeats": 1, "main": ["effort": "easy", "meters": 5000]]]])
        #expect(try SharedWorkout.decode(data).name == "Shared workout")
    }

    @Test func readsTheFileIOSHandsOver() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).trackstar")
        defer { try? FileManager.default.removeItem(at: url) }
        let shared = SharedWorkout(template: template, paces: senderPaces)
        try shared.encoded().write(to: url)
        #expect(SharedWorkout.canOpen(url))
        #expect(!SharedWorkout.canOpen(URL(string: "io.github.nickcia.runcoach://strava")!))
        #expect(try SharedWorkout.read(from: url) == shared)
    }

    // MARK: Saving into the plan

    @Test func sharingGoesFromOnePlanIntoAnother() throws {
        let sender = try AppModelTests.startedModel(today: AppModelTests.start.adding(days: 7))
        let own = try #require(sender.addWorkout(template, on: sender.today.adding(days: 1)))
        let shared = try #require(sender.sharedWorkout(for: own))
        #expect(shared.blocks.count == template.blocks.count)

        let friend = try AppModelTests.startedModel(today: AppModelTests.start.adding(days: 7))
        let planned = try #require(friend.plan?.workouts.first { $0.date > friend.today && $0.kind == .easy })
        let received = try SharedWorkout.decode(try shared.encoded())
        let added = try #require(friend.addSharedWorkout(received, paces: .mine, on: planned.date, keep: true))
        #expect(added.isCustom)
        #expect(added.name == "Saturday tempo")
        #expect(friend.workout(on: planned.date)?.id == added.id)
        #expect(friend.scheduledWorkouts.count == 1)
        #expect(friend.savedWorkouts.map(\.name) == ["Saturday tempo"])
        // The plan's run comes back if they take it off again.
        friend.removeWorkout(added)
        #expect(friend.workout(on: planned.date)?.id == planned.id)
    }

    @Test func sharedPlannedWorkoutSavesAtTheSendersPaces() throws {
        let sender = try AppModelTests.startedModel(today: AppModelTests.start)
        let tempo = try #require(sender.plan?.workouts.first { $0.kind == .tempo })
        let shared = try #require(sender.sharedWorkout(for: tempo))
        let friend = try AppModelTests.startedModel(today: AppModelTests.start.adding(days: 7))
        let day = friend.today.adding(days: 2)
        let added = try #require(friend.addSharedWorkout(shared, paces: .theirs, on: day, keep: false))
        #expect(friend.savedWorkouts.isEmpty)
        #expect(added.expandedSteps.map(\.target?.range) == tempo.expandedSteps.map(\.target?.range))
    }

    @Test func notOnDaysTheFriendCantUse() throws {
        let friend = try AppModelTests.startedModel(today: AppModelTests.start.adding(days: 7))
        let shared = SharedWorkout(template: template, paces: senderPaces)
        let race = try #require(friend.plan?.inputs.raceDate)
        #expect(friend.addSharedWorkout(shared, paces: .mine, on: friend.today.adding(days: -1), keep: true) == nil)
        #expect(friend.addSharedWorkout(shared, paces: .mine, on: race, keep: true) == nil)
        // Nothing is kept from a workout that couldn't go on.
        #expect(friend.savedWorkouts.isEmpty)
        #expect(friend.scheduledWorkouts.isEmpty)
    }
}
