import Foundation
import Testing
import PlanEngine
@testable import TrackStar

/// A pretend TrackStar server: registers devices, hands out a Garmin sign-in page, takes workouts and holds runs.
nonisolated final class FakeServer: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [String] = []
    private var _workoutBodies: [Data] = []
    private var _inbox: [(id: String, run: String)] = []
    private var _connected = true
    private var _stravaBodies: [String] = []
    private var registrations = 0

    var requests: [String] { lock.withLock { _requests } }
    var workoutBodies: [Data] { lock.withLock { _workoutBodies } }
    var inboxCount: Int { lock.withLock { _inbox.count } }
    var stravaBodies: [String] { lock.withLock { _stravaBodies } }
    var registrationCount: Int { lock.withLock { registrations } }
    func addRun(_ json: String) { lock.withLock { _inbox.append((UUID().uuidString, json)) } }
    func setConnected(_ connected: Bool) { lock.withLock { _connected = connected } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { handle(request) }
    }

    private func handle(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let path = request.url!.path
        _requests.append("\(method) \(path)")
        if method == "POST", path == "/v1/devices" {
            registrations += 1
            return reply(201, #"{"id":"device-\#(registrations)-aaaaaaaaaaaa","secret":"secret-secret-secret-secret-secret-1"}"#)
        }
        guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Device device-") == true else {
            return reply(401, #"{"error":"Unknown device"}"#)
        }
        switch (method, path) {
        case ("POST", "/v1/garmin/start"):
            return reply(200, #"{"url":"https://connect.garmin.com/oauth2Confirm?state=abc"}"#)
        case ("GET", "/v1/garmin"):
            return reply(200, _connected ? #"{"connected":true,"needsReconnect":false,"sendsWorkouts":true,"sharesRuns":true}"# : #"{"connected":false}"#)
        case ("DELETE", "/v1/garmin"):
            _inbox = []
            return reply(200, #"{"connected":false}"#)
        case ("PUT", "/v1/garmin/workouts"):
            _workoutBodies.append(request.httpBody ?? Data())
            return reply(200, #"{"added":3,"removed":0,"waiting":0}"#)
        case ("GET", "/v1/garmin/runs"):
            let items = _inbox.prefix(20).map { #"{"id":"\#($0.id)","run":\#($0.run)}"# }.joined(separator: ",")
            return reply(200, #"{"runs":[\#(items)]}"#)
        case ("POST", "/v1/garmin/runs/received"):
            let ids = (try? JSONDecoder().decode([String: [String]].self, from: request.httpBody ?? Data()))?["ids"] ?? []
            _inbox.removeAll { ids.contains($0.id) }
            return reply(200, #"{"ok":true}"#)
        case ("POST", "/v1/strava/token"):
            _stravaBodies.append(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
            return reply(200, #"{"access_token":"token-1","refresh_token":"refresh-1","expires_at":\#(Int(Date.now.timeIntervalSince1970) + 21600),"athlete":{"id":7,"firstname":"Test","lastname":"Runner"}}"#)
        default:
            return reply(404, #"{"error":"Not found"}"#)
        }
    }

    private func reply(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://server.test")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

// Serialized: these tests share the "Garmin connected" flag in UserDefaults.
@MainActor @Suite(.serialized)
struct GarminTests {
    static let today = AppModelTests.start.adding(days: 3)

    func makeServer(_ fake: FakeServer) -> TrackStarServer {
        TrackStarServer(baseURL: URL(string: "https://server.test")!, transport: fake,
                        keychain: ServerDeviceKeychain(service: "trackstar-tests-\(UUID().uuidString)"))
    }

    func makeModel(_ fake: FakeServer, health: FakeRunSource? = nil,
                   store: GarminRunStore = GarminRunStore(file: URL.temporaryDirectory.appending(path: "garmin-\(UUID().uuidString)/runs.json"))) throws -> AppModel {
        UserDefaults.standard.removeObject(forKey: "garmin.connected")
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { Self.today },
                             runSource: health, server: makeServer(fake), garminStore: store)
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(AppModelTests.inputs()))
        return model
    }

    /// A run as the server passes it on: `start` is UTC, `offset` the local time zone's.
    static func runJSON(id: String, date: LocalDate, meters: Double, seconds: Double, device: String? = "Forerunner 265") -> String {
        // 07:00 local in Toronto (UTC-5).
        let start = date.date(in: utc).timeIntervalSince1970 + 12 * 3600
        let samples = (0..<4).map { i in "[\(start + Double(i) * 5),\(140 + i),3.2,\(Double(i) * 16),\(88),-1,-9999]" }.joined(separator: ",")
        let deviceField = device.map { "\"\($0)\"" } ?? "null"
        return #"{"id":"\#(id)","start":\#(start),"offset":-18000,"duration":\#(seconds),"distance":\#(meters),"device":\#(deviceField),"name":"Toronto Running","manual":false,"samples":[\#(samples)]}"#
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func connect(_ model: AppModel) async throws {
        try await model.finishGarminSignIn(callback: URL(string: "io.github.nickcia.runcoach://garmin?garmin=connected")!)
    }

    // MARK: Workouts

    @Test func workoutsBecomeStepsWithRepeatsAndPaces() throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        func paced(_ block: IntervalBlock) -> Bool {
            block.iterations > 1 && block.steps.contains { step in
                step.step.target.map { $0.zone != .stride && $0.zone != .hill } ?? false
            }
        }
        let workout = try #require(plan.workouts.first { !$0.isRunWalkSession && $0.blocks.contains(where: paced) })
        let converted = GarminWorkoutBuilder.workout(for: workout, format: DisplayFormat(units: .metric))
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(converted)) as? [String: Any])
        #expect(json["date"] as? String == workout.date.description)
        #expect((json["key"] as? String)?.hasPrefix("trackstar-\(workout.id)-") == true)
        let steps = try #require(json["steps"] as? [[String: Any]])
        let block = try #require(workout.blocks.first(where: paced))
        let repeated = try #require(steps.first { $0["kind"] as? String == "repeat" && $0["times"] as? Int == block.iterations })
        let inner = try #require(repeated["steps"] as? [[String: Any]])
        let paced = try #require(inner.first { $0["pace"] != nil })
        let pace = try #require(paced["pace"] as? [String: Double])
        #expect(pace["fast"]! < pace["slow"]!)
        if workout.warmup != nil { #expect(steps.first?["intensity"] as? String == "warmup") }
    }

    @Test func keysChangeWhenAWorkoutChanges() throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        var workout = plan.workouts[3]
        let format = DisplayFormat(units: .metric)
        let first = GarminWorkoutBuilder.workout(for: workout, format: format).key
        #expect(GarminWorkoutBuilder.workout(for: workout, format: format).key == first)
        workout.date = workout.date.adding(days: 1)
        #expect(GarminWorkoutBuilder.workout(for: workout, format: format).key != first)
    }

    @Test func onlyTheNextTwoWeeksAreSent() throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let sent = GarminWorkoutBuilder.workouts(plan.workouts, from: Self.today, format: DisplayFormat(units: .metric))
        #expect(!sent.isEmpty)
        #expect(sent.allSatisfy { $0.date >= Self.today.description && $0.date <= Self.today.adding(days: 15).description })
    }

    // MARK: Runs

    @Test func runsAreReadOnTheirOwnDayWithDataAndCredit() throws {
        let day = LocalDate(year: 2026, month: 11, day: 5)
        let run = try JSONDecoder().decode(GarminRun.self, from: Data(Self.runJSON(id: "77", date: day, meters: 8000, seconds: 2400).utf8))
        #expect(run.date == day)
        #expect(run.completedRun?.id == "garmin-77")
        #expect(run.completedRun?.distanceMeters == 8000)
        #expect(run.attribution == "Garmin Forerunner 265")
        let series = try #require(run.series)
        #expect(series.heartRate.map(\.t) == [0, 5, 10, 15])
        #expect(series.distance.last?.v == 48)
        #expect(series.cadence.first?.v == 176)  // Per-foot cadence doubled.
        #expect(series.power.isEmpty && series.altitude.isEmpty)

        let unknown = try JSONDecoder().decode(GarminRun.self, from: Data(Self.runJSON(id: "78", date: day, meters: 8000, seconds: 2400, device: nil).utf8))
        #expect(unknown.attribution == "Garmin")
    }

    // MARK: Connecting

    @Test func connectingSendsWorkoutsAndCollectsRuns() async throws {
        let fake = FakeServer()
        let model = try makeModel(fake)
        let workout = try #require(model.plan?.workouts.first { $0.date <= Self.today })
        fake.addRun(Self.runJSON(id: "1", date: workout.date, meters: workout.totalMeters, seconds: workout.totalSeconds))
        try await connect(model)

        #expect(model.garminConnected)
        #expect(model.syncableWatches.contains("Garmin"))
        #expect(fake.registrationCount == 1)
        let body = try #require(fake.workoutBodies.first)
        let sent = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["workouts"] as? [[String: Any]])
        #expect(!sent.isEmpty)

        // The run came over, ticked off its workout, and the server's copy was cleared.
        #expect(fake.inboxCount == 0)
        let run = try #require(model.healthRuns.first { $0.id == "garmin-1" })
        #expect(model.healthRun(for: workout)?.id == "garmin-1")
        #expect(model.garminAttribution(for: run) == "Garmin Forerunner 265")
        #expect(model.sourceName(for: run) == "Garmin Forerunner 265")
        #expect(model.runSeries["garmin-1"] != nil)
        // Never given to the coach.
        #expect(!model.coachRuns.contains { $0.id == "garmin-1" })
        #expect(model.includesGarminRuns)

        await model.disconnectGarmin()
    }

    @Test func unchangedPlansArentSentAgain() async throws {
        let fake = FakeServer()
        let model = try makeModel(fake)
        try await connect(model)
        let count = fake.workoutBodies.count
        await model.syncGarmin()
        #expect(fake.workoutBodies.count == count)
        await model.syncGarmin(force: true)
        #expect(fake.workoutBodies.count == count + 1)
        await model.disconnectGarmin()
    }

    @Test func aRunAlsoInHealthCountsOnce() async throws {
        let fake = FakeServer()
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let workout = try #require(plan.workouts.first { $0.date <= Self.today })
        let health = FakeRunSource(runs: [HealthIntegrationTests.run(for: workout, id: "health-1")])
        let model = try makeModel(fake, health: health)
        await model.connectHealth()
        fake.addRun(Self.runJSON(id: "2", date: workout.date, meters: workout.totalMeters * 1.02, seconds: workout.totalSeconds))
        try await connect(model)
        #expect(model.healthRuns.filter { $0.date == workout.date }.map(\.id) == ["health-1"])
        await model.disconnectGarmin()
    }

    @Test func runsAreKeptOnThePhoneAcrossLaunches() async throws {
        let fake = FakeServer()
        let store = GarminRunStore(file: URL.temporaryDirectory.appending(path: "garmin-\(UUID().uuidString)/runs.json"))
        let model = try makeModel(fake, store: store)
        let workout = try #require(model.plan?.workouts.first { $0.date <= Self.today })
        fake.addRun(Self.runJSON(id: "3", date: workout.date, meters: workout.totalMeters, seconds: workout.totalSeconds))
        try await connect(model)
        #expect(store.load().map(\.id) == ["3"])

        // Disconnecting deletes them here and on the server.
        await model.disconnectGarmin()
        #expect(fake.requests.contains("DELETE /v1/garmin"))
        #expect(!model.garminConnected)
        #expect(store.load().isEmpty)
        #expect(!model.healthRuns.contains { $0.id == "garmin-3" })
    }

    @Test func removingTrackStarInGarminConnectForgetsTheConnection() async throws {
        let fake = FakeServer()
        let model = try makeModel(fake)
        try await connect(model)
        fake.setConnected(false)
        await model.refreshGarminStatus()
        #expect(!model.garminConnected)
        #expect(UserDefaults.standard.object(forKey: "garmin.connected") == nil)
    }

    @Test func aDeclinedSignInDoesntConnect() async throws {
        let model = try makeModel(FakeServer())
        await #expect(throws: GarminConnectError.declined) {
            try await model.finishGarminSignIn(callback: URL(string: "io.github.nickcia.runcoach://garmin?garmin=declined")!)
        }
        #expect(!model.garminConnected)
    }

    // MARK: Strava through the server

    @Test func stravaSignInGoesThroughTheServerWithoutASecret() async throws {
        let server = FakeServer()
        let oauth = StravaOAuth(clientID: "42", clientSecret: nil, redirectURI: "io.github.nickcia.runcoach://nickcia.github.io/strava",
                                relay: makeServer(server))
        let strava = FakeStrava()
        let credentials = try await StravaClient(transport: strava).signIn(code: "good-code", oauth: oauth)
        #expect(credentials.accessToken == "token-1")
        #expect(credentials.athleteName == "Test Runner")
        // Nothing went to Strava directly, and no secret left the phone.
        #expect(strava.requests.isEmpty)
        let body = try #require(server.stravaBodies.first)
        #expect(body.contains("good-code") && body.contains("authorization_code"))
        #expect(!body.contains("secret"))
    }
}
