import Foundation
import Testing
import PlanEngine
@testable import TrackStar

@MainActor
struct HelpSearchTests {
    @Test func everydayQuestionsFindTheRightArticle() {
        #expect(AppHelp.search("how do I connect my garmin?").first?.id == "garmin")
        #expect(AppHelp.search("Can I sync my Forerunner").first?.id == "garmin")
        #expect(AppHelp.search("how do I add vacation time").first?.id == "timeoff")
        #expect(AppHelp.search("set the treadmill to km").first?.id == "treadmill")
        #expect(AppHelp.search("I'm injured, what do I do in the app").first?.id == "injury")
        #expect(AppHelp.search("change to miles").first?.id == "units")
        #expect(AppHelp.search("heart rate zones").first?.id == "heartrate")
        #expect(AppHelp.search("my runs aren't showing up").first?.id == "health")
        #expect(AppHelp.search("purple elephant").isEmpty)
    }
}

@MainActor
struct CoachTimeOffTests {
    @Test func noticesInjuryIllnessAndHolidays() {
        #expect(CoachSnapshot.timeOffReason(in: "I think I injured my calf yesterday") == .injury)
        #expect(CoachSnapshot.timeOffReason(in: "I have a cold, should I run?") == .illness)
        #expect(CoachSnapshot.timeOffReason(in: "Going on holiday next week") == .vacation)
        #expect(CoachSnapshot.timeOffReason(in: "How did my long run go?") == nil)
        // The coach's own offer counts; a passing mention doesn't.
        #expect(CoachSnapshot.timeOffOffer(in: "Would you like to mark this as an injury and pause the plan?") == .injury)
        #expect(CoachSnapshot.timeOffOffer(in: "Run easy to avoid injury.") == nil)
        #expect(CoachSnapshot.timeOffOffer(in: "Let me know if you'd like to mark this as time off.") == .other)
        #expect(CoachSnapshot.timeOffReason(in: "my knee is sore after the long run") == .injury)
    }
}

@MainActor
struct TimeOffModelTests {
    func model() throws -> AppModel {
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { AppModelTests.start.adding(days: 9) })
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(AppModelTests.inputs()))
        return model
    }

    @Test func addingTimeOffClearsThoseDays() throws {
        let model = try model()
        let start = model.today.adding(days: 2)
        let holiday = TimeOff(reason: .vacation, start: start, end: start.adding(days: 6))
        #expect(model.changeTimeOff([holiday]))
        #expect(model.timeOff == [holiday])
        #expect(model.plan?.workouts.contains { holiday.contains($0.date) } == false)
        #expect(model.unseenChange?.reasons == [.timeOffChanged])
    }

    @Test func comingBackEarlyEndsItYesterday() throws {
        let model = try model()
        let injury = TimeOff(reason: .injury, start: model.today.adding(days: -3), end: nil)
        model.changeTimeOff([injury])
        #expect(model.currentTimeOff?.id == injury.id)
        #expect(model.plan?.workouts.filter { $0.date >= model.today && $0.kind != .race }.isEmpty == true)

        let ended = model.timeOffEndingToday(injury)
        #expect(ended.first?.end == model.today.adding(days: -1))
        model.changeTimeOff(ended)
        #expect(model.currentTimeOff == nil)
        // Running is back, starting easy.
        let next = try #require(model.plan?.workouts.first { $0.date >= model.today })
        #expect(next.kind == .easy)

        // Time off that hadn't started yet just goes.
        let later = TimeOff(reason: .busy, start: model.today.adding(days: 20), end: model.today.adding(days: 22))
        model.changeTimeOff(model.timeOff + [later])
        #expect(!model.timeOffEndingToday(later).contains { $0.id == later.id })
    }
}
