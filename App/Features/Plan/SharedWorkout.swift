import CoreTransferable
import Foundation
import PlanEngine
import UniformTypeIdentifiers

// Sharing a workout: the runner sends a workout to a friend as a small ".trackstar" file, the friend opens it in
// TrackStar, sees the steps and paces, and puts it on a day of their own plan to run the same session together.
//
// A file rather than a link: there are no accounts and no web domain, and a file opens TrackStar straight from
// AirDrop and works in Messages, Mail, WhatsApp and Files alike, where a custom-scheme link often isn't tappable.
// The file holds each step's effort (Zone 2, threshold…) and the sender's pace for it, so the friend can run it at
// their own paces or at exactly the sender's.

extension UTType {
    /// A workout shared from TrackStar (".trackstar"), declared in the app's Info.plist.
    nonisolated static var trackStarWorkout: UTType {
        UTType(exportedAs: (Bundle.main.bundleIdentifier ?? "io.github.nickcia.runcoach") + ".workout")
    }
}

/// A workout as it travels between two people's TrackStar apps.
nonisolated struct SharedWorkout: Codable, Hashable, Sendable {
    static let formatName = "trackstar.workout"
    /// The format this app writes and reads. Bump it for any change; bump `minimumVersion` in written files only
    /// when older apps would read the new file wrongly (new optional fields don't need that).
    static let currentVersion = 1
    static let fileExtension = "trackstar"
    /// Real files are a couple of kilobytes; anything far bigger isn't one of ours.
    static let maxBytes = 64 * 1024

    var format = SharedWorkout.formatName
    var version = SharedWorkout.currentVersion
    /// The oldest app version that can read this file.
    var minimumVersion = 1
    var name: String
    var blocks: [Block]

    private enum CodingKeys: String, CodingKey { case format, version, minimumVersion, name, blocks }

    init(name: String, blocks: [Block]) {
        self.name = name
        self.blocks = blocks
    }

    /// Fields with defaults may be missing from a file (`minimumVersion` from the first files, say).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        minimumVersion = try container.decodeIfPresent(Int.self, forKey: .minimumVersion) ?? 1
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        blocks = try container.decode([Block].self, forKey: .blocks)
    }

    /// One stretch of running: an effort for a time or a distance.
    struct Part: Codable, Hashable, Sendable {
        /// An `Effort` raw value. One this app doesn't know (from a newer app) is run at the sender's pace.
        var effort: String
        var meters: Double?
        var seconds: Double?
        /// The sender's pace for this part in s/km; nil when it has no pace target.
        var pace: PaceRange?
    }

    /// A warm-up, a run, a set of repeats or a cool-down (as `WorkoutBlock`).
    struct Block: Codable, Hashable, Sendable {
        var role: String
        var repeats: Int
        var main: Part
        var recovery: Part?
    }

    enum Problem: Error, Equatable, LocalizedError {
        /// Not a TrackStar workout, or damaged on the way.
        case unreadable
        /// From a newer TrackStar that this one can't read.
        case newerVersion

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "This isn't a TrackStar workout, or it was damaged on the way. Ask for it to be shared again.")
            case .newerVersion: String(localized: "This workout was shared from a newer version of TrackStar. Update the app to open it.")
            }
        }
    }

    /// Whose paces the friend runs it at.
    enum PaceChoice: String, CaseIterable, Identifiable, Sendable {
        /// Each zone at the friend's own pace.
        case mine
        /// The sender's exact paces, to run side by side.
        case theirs
        var id: String { rawValue }
    }
}

// MARK: - Making one

extension SharedWorkout {
    /// A custom workout as shared, with the sender's paces for each part.
    init(template: WorkoutTemplate, paces: PaceTable) {
        self.init(name: template.name, blocks: template.blocks.map { block in
            Block(role: block.role.rawValue, repeats: block.role == .repeats ? max(1, block.repeats) : 1,
                  main: Part(block.main, paces: paces),
                  recovery: block.role == .repeats ? block.recovery.map { Part($0, paces: paces) } : nil)
        })
    }

    /// Any run on the plan, or nil for one that can't be shared. Race day is the sender's own race; strength
    /// sessions and rest days aren't workouts, so never reach here.
    init?(workout: Workout, template: WorkoutTemplate?, paces: PaceTable) {
        guard workout.kind != .race else { return nil }
        var shared = SharedWorkout(template: template ?? WorkoutTemplate(sharing: workout), paces: paces)
        shared.name = workout.name
        guard !shared.blocks.isEmpty else { return nil }
        self = shared
    }

    /// "Tempo-run.trackstar"
    nonisolated var fileName: String {
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|").union(.newlines)).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return "\(safe.isEmpty ? "Workout" : String(safe.prefix(60))).\(Self.fileExtension)"
    }

    nonisolated func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

extension SharedWorkout.Part {
    init(_ part: BlockPart, paces: PaceTable) {
        effort = part.effort.rawValue
        switch part.length {
        case .distance(let meters): self.meters = meters
        case .time(let seconds): self.seconds = seconds
        }
        pace = part.pace(paces)
    }
}

extension WorkoutTemplate {
    /// A planned workout as blocks, so it can be shared and saved like one the athlete built. Each step keeps its
    /// effort; steps without a pace target (recovery jogs, walks, hill efforts) are run by feel.
    init(sharing workout: Workout) {
        var blocks: [WorkoutBlock] = []
        if let warmup = workout.warmup { blocks.append(WorkoutBlock(role: .warmup, main: BlockPart(sharing: warmup, recovery: false))) }
        for block in workout.blocks {
            let steps = block.steps
            if steps.count == 1 {
                let main = BlockPart(sharing: steps[0].step, recovery: steps[0].purpose == .recovery)
                blocks.append(block.iterations > 1 ? WorkoutBlock(role: .repeats, main: main, repeats: block.iterations)
                                                   : WorkoutBlock(role: .run, main: main))
            } else if steps.count == 2, steps[0].purpose == .work, steps[1].purpose == .recovery {
                blocks.append(WorkoutBlock(role: .repeats, main: BlockPart(sharing: steps[0].step, recovery: false),
                                           repeats: max(1, block.iterations),
                                           recovery: BlockPart(sharing: steps[1].step, recovery: true)))
            } else {
                // No shape like this in the plan today; spell it out step by step.
                for _ in 0..<min(max(1, block.iterations), 20) {
                    blocks += steps.map { WorkoutBlock(role: .run, main: BlockPart(sharing: $0.step, recovery: $0.purpose == .recovery)) }
                }
            }
        }
        if let cooldown = workout.cooldown { blocks.append(WorkoutBlock(role: .cooldown, main: BlockPart(sharing: cooldown, recovery: false))) }
        self.init(name: workout.name, blocks: blocks)
    }
}

extension BlockPart {
    init(sharing step: Step, recovery: Bool) {
        let effort: Effort = switch step.target?.zone {
        case nil, .hill?: .open
        case .easy?: recovery ? .recovery : .easy
        case .marathon?: .steady
        case .threshold?: .threshold
        case .interval?: .vo2max
        case .repetition?, .stride?: .speed
        case .race?: .racePace
        }
        self.init(effort: effort, length: step.goal)
    }
}

// MARK: - Reading one

extension SharedWorkout {
    /// Reads a shared workout, checking it's one of ours, from a version this app understands, and sensible.
    static func decode(_ data: Data) throws(Problem) -> SharedWorkout {
        struct Header: Decodable {
            var format: String
            var version: Int
            var minimumVersion: Int?
        }
        guard !data.isEmpty, data.count <= maxBytes,
              let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == formatName, header.version >= 1 else { throw .unreadable }
        guard (header.minimumVersion ?? 1) <= currentVersion else { throw .newerVersion }
        guard let workout = try? JSONDecoder().decode(SharedWorkout.self, from: data) else {
            // A newer file we should have been able to read but couldn't: still the newer app's doing.
            throw header.version > currentVersion ? .newerVersion : .unreadable
        }
        return try workout.validated()
    }

    /// Whether TrackStar should open this URL as a shared workout.
    static func canOpen(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == fileExtension
    }

    /// Reads a ".trackstar" file handed over by iOS (from AirDrop, Messages, Files…), then tidies up the copy iOS
    /// put in the app's Inbox.
    static func read(from url: URL) throws(Problem) -> SharedWorkout {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes { throw .unreadable }
        guard let data = try? Data(contentsOf: url) else { throw .unreadable }
        return try decode(data)
    }

    private func validated() throws(Problem) -> SharedWorkout {
        guard (1...60).contains(blocks.count) else { throw .unreadable }
        var copy = self
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? String(localized: "Shared workout") : String(trimmed.prefix(80))
        for block in blocks {
            guard (1...99).contains(block.repeats), block.main.isValid, block.recovery?.isValid ?? true else { throw .unreadable }
        }
        return copy
    }
}

extension SharedWorkout.Part {
    fileprivate var isValid: Bool {
        // Exactly one of time and distance, within what anyone would run.
        let length: Bool = switch (meters, seconds) {
        case (let meters?, nil): meters.isFinite && (1...200_000).contains(meters)
        case (nil, let seconds?): seconds.isFinite && (1...(12 * 3600)).contains(seconds)
        default: false
        }
        guard let pace else { return length }
        return length && pace.fast.isFinite && pace.slow.isFinite && (60...1800).contains(pace.fast)
            && (pace.fast...1800).contains(pace.slow)
    }
}

// MARK: - Saving one

extension SharedWorkout {
    /// Whether any part has a pace to choose between the friend's and the sender's.
    var hasPaces: Bool {
        blocks.contains { block in ([block.main] + [block.recovery].compactMap { $0 }).contains { $0.pace != nil } }
    }

    /// The workout as one of the friend's own, at their paces or the sender's.
    func template(paces choice: PaceChoice) -> WorkoutTemplate {
        WorkoutTemplate(name: name, blocks: blocks.map { block in
            let role = WorkoutBlock.Role(rawValue: block.role) ?? .run
            return WorkoutBlock(role: role, main: block.main.part(choice), repeats: role == .repeats ? block.repeats : 1,
                                recovery: role == .repeats ? block.recovery.map { $0.part(choice) } : nil)
        })
    }
}

extension SharedWorkout.Part {
    func part(_ choice: SharedWorkout.PaceChoice) -> BlockPart {
        let length: StepGoal = meters.map { .distance(meters: $0) } ?? .time(seconds: seconds ?? 0)
        guard let effort = Effort(rawValue: effort) else {
            // An effort from a newer app: the sender's pace is all there is to go on.
            return pace.map { BlockPart(effort: .steady, length: length, customPace: $0) } ?? BlockPart(effort: .open, length: length)
        }
        return BlockPart(effort: effort, length: length,
                         customPace: choice == .theirs && effort != .open ? pace : nil)
    }
}

extension AppModel {
    /// The workout as the athlete would share it; nil for one that can't be shared (race day).
    func sharedWorkout(for workout: Workout) -> SharedWorkout? {
        guard let paces = plan?.paces else { return nil }
        return SharedWorkout(workout: workout, template: scheduled(workout)?.template, paces: paces)
    }

    /// Puts a shared workout on a day of the plan like one the athlete built (to the watch and calendar with the
    /// rest), and in My workouts too if they want to keep it.
    @discardableResult
    func addSharedWorkout(_ shared: SharedWorkout, paces choice: SharedWorkout.PaceChoice, on date: LocalDate,
                          keep: Bool) -> Workout? {
        let template = shared.template(paces: choice)
        guard canAddWorkout(on: date) else { return nil }
        if keep { saveWorkout(template) }
        return addWorkout(template, on: date)
    }
}

// MARK: - Sending one

/// A shared workout as a ".trackstar" file for the share sheet.
nonisolated struct SharedWorkoutFile: Transferable {
    let workout: SharedWorkout

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .trackStarWorkout) { file in
            let folder = FileManager.default.temporaryDirectory.appending(path: "Shared workouts/\(UUID().uuidString)",
                                                                           directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: file.workout.fileName)
            try file.workout.encoded().write(to: url)
            return SentTransferredFile(url)
        }
    }
}
