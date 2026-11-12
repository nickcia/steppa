import Foundation
import SwiftData
import PlanEngine

// Gear: running shoes (with the distance run in them) and the devices the athlete runs with.
// Same CloudKit rules as Records.swift: every property defaulted or optional, no unique constraints, no relationships.

nonisolated enum GearKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shoes, watch, heartRateMonitor

    var id: String { rawValue }

    var name: String {
        switch self {
        case .shoes: String(localized: "Shoes")
        case .watch: String(localized: "Watch")
        case .heartRateMonitor: String(localized: "Heart-rate monitor")
        }
    }

    var symbol: String {
        switch self {
        case .shoes: "shoe.fill"
        case .watch: "applewatch"
        case .heartRateMonitor: "heart.fill"
        }
    }
}

/// What a pair of shoes is for. Sets the suggested retirement distance; the athlete can change it.
nonisolated enum ShoeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily, lightweight, race, trail

    var id: String { rawValue }

    var name: String {
        switch self {
        case .daily: String(localized: "Daily trainer")
        case .lightweight: String(localized: "Tempo or lightweight trainer")
        case .race: String(localized: "Racing shoe")
        case .trail: String(localized: "Trail shoe")
        }
    }

    /// Typical replacement distance: a guide, not a limit. Shoe makers (ASICS, Brooks) and the American Academy of
    /// Podiatric Sports Medicine give 300–500 miles (≈500–800 km) for trainers. Light foams and thin outsoles wear
    /// sooner, and super-shoe foams lose their running-economy edge by about 450 km (Rodrigo-Carranza et al., 2023).
    var suggestedRetirementMeters: Double {
        switch self {
        case .daily: 700_000
        case .lightweight: 500_000
        case .race: 300_000
        case .trail: 700_000
        }
    }
}

/// A shoe, watch or heart-rate monitor.
@Model
final class GearRecord {
    var gearID: UUID = UUID()
    var kindRaw: String = GearKind.shoes.rawValue
    var name: String = ""
    var brand: String = ""
    var shoeTypeRaw: String = ShoeType.daily.rawValue
    /// Distance already run in the shoes before TrackStar started counting.
    var startingMeters: Double = 0
    /// When to suggest replacing them. nil uses the shoe type's suggestion.
    var retirementMeters: Double?
    var retired: Bool = false
    var retiredAt: Date?
    /// New runs are counted in these shoes.
    var isDefault: Bool = false
    /// `YYYY-MM-DD`: runs from this day on are counted (as text, so a time-zone change can't move it).
    var sinceString: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(kind: GearKind, name: String, brand: String = "", shoeType: ShoeType = .daily,
         startingMeters: Double = 0, since: LocalDate) {
        self.kindRaw = kind.rawValue
        self.name = name
        self.brand = brand
        self.shoeTypeRaw = shoeType.rawValue
        self.startingMeters = startingMeters
        self.sinceString = since.description
    }

    var kind: GearKind {
        get { GearKind(rawValue: kindRaw) ?? .shoes }
        set { kindRaw = newValue.rawValue }
    }

    var shoeType: ShoeType {
        get { ShoeType(rawValue: shoeTypeRaw) ?? .daily }
        set { shoeTypeRaw = newValue.rawValue }
    }

    var since: LocalDate {
        get { LocalDate(iso: sinceString) ?? LocalDate(createdAt) }
        set { sinceString = newValue.description }
    }

    var retireAt: Double { retirementMeters ?? shoeType.suggestedRetirementMeters }

    /// "Nike Pegasus 41", or just the name when the brand is already in it.
    var displayName: String {
        let brand = brand.trimmingCharacters(in: .whitespaces)
        let name = name.trimmingCharacters(in: .whitespaces)
        if brand.isEmpty || name.localizedCaseInsensitiveContains(brand) { return name.isEmpty ? brand : name }
        return name.isEmpty ? brand : "\(brand) \(name)"
    }
}

/// Which shoes a run was done in. One per run; `gearID` nil means "no shoes counted" (the athlete took it off).
/// The run's date and distance are kept so the run is still recognised if it comes back under another ID (a Garmin
/// run that later shows up in Apple Health), and so the count survives runs leaving the app's window.
@Model
final class ShoeRunRecord {
    var runID: String = ""
    var gearID: UUID?
    var dateString: String = ""
    var distanceMeters: Double = 0
    /// Chosen by the athlete rather than counted automatically.
    var manual: Bool = false
    var updatedAt: Date = Date.now

    init(run: CompletedRun, gearID: UUID?, manual: Bool) {
        self.runID = run.id
        self.gearID = gearID
        self.dateString = run.date.description
        self.distanceMeters = run.distanceMeters
        self.manual = manual
    }

    var entry: ShoeMileage.Entry {
        ShoeMileage.Entry(runID: runID, gearID: gearID, date: LocalDate(iso: dateString) ?? LocalDate(updatedAt),
                          distanceMeters: distanceMeters, updatedAt: updatedAt)
    }
}

/// How worn a pair of shoes is against its retirement distance.
enum ShoeWear: Equatable {
    case fine
    /// Within the last 15% of the retirement distance.
    case nearing
    case due

    static let nearingFraction = 0.85

    init(distance: Double, retireAt: Double) {
        guard retireAt > 0 else { self = .fine; return }
        let fraction = distance / retireAt
        self = fraction >= 1 ? .due : fraction >= Self.nearingFraction ? .nearing : .fine
    }
}

/// The counting rules, kept free of storage so they can be tested on their own.
enum ShoeMileage {
    struct Entry: Equatable {
        var runID: String
        var gearID: UUID?
        var date: LocalDate
        var distanceMeters: Double
        var updatedAt: Date = .distantPast
    }

    /// One entry per run: the latest wins when two devices counted the same run.
    static func latest(_ entries: [Entry]) -> [Entry] {
        Dictionary(entries.map { ($0.runID, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
            .values.sorted { $0.date < $1.date }
    }

    /// The entry for a run: by ID, or the same run under another ID (same day, distance within 5%).
    static func entry(for run: CompletedRun, in entries: [Entry]) -> Entry? {
        entries.first { $0.runID == run.id }
            ?? entries.first { AppModel.sameRun(CompletedRun(id: $0.runID, date: $0.date, distanceMeters: $0.distanceMeters,
                                                             durationSeconds: 0), run) }
    }

    /// Runs that should be counted in the default shoes now: not counted yet, and on or after the day the shoes were
    /// put into use.
    static func runsToCount(_ runs: [CompletedRun], entries: [Entry], defaultSince: LocalDate?) -> [CompletedRun] {
        guard let defaultSince else { return [] }
        return runs.filter { $0.date >= defaultSince && $0.distanceMeters > 0 && entry(for: $0, in: entries) == nil }
    }

    /// Everything run in a pair of shoes: what was there before, plus each counted run once.
    static func distance(of gearID: UUID, startingMeters: Double, entries: [Entry]) -> Double {
        startingMeters + latest(entries).filter { $0.gearID == gearID }.reduce(0) { $0 + $1.distanceMeters }
    }
}

// MARK: - AppModel

extension AppModel {
    var shoes: [GearRecord] { gear.filter { $0.kind == .shoes } }
    var activeShoes: [GearRecord] { shoes.filter { !$0.retired } }

    /// The shoes new runs go to. If two devices each set one before syncing, the latest change wins.
    var defaultShoes: GearRecord? {
        activeShoes.filter(\.isDefault).max { $0.updatedAt < $1.updatedAt }
    }

    private var shoeEntries: [ShoeMileage.Entry] { shoeRuns.map(\.entry) }

    func distance(in shoes: GearRecord) -> Double {
        ShoeMileage.distance(of: shoes.gearID, startingMeters: shoes.startingMeters, entries: shoeEntries)
    }

    func runCount(in shoes: GearRecord) -> Int {
        ShoeMileage.latest(shoeEntries).filter { $0.gearID == shoes.gearID }.count
    }

    func wear(of shoes: GearRecord) -> ShoeWear {
        ShoeWear(distance: distance(in: shoes), retireAt: shoes.retireAt)
    }

    /// Active shoes nearing or past their retirement distance, most worn first.
    var shoesToReplace: [GearRecord] {
        activeShoes.filter { wear(of: $0) != .fine }
            .sorted { distance(in: $0) / $0.retireAt > distance(in: $1) / $1.retireAt }
    }

    /// The shoes a run was counted in; nil if none.
    func shoes(for run: CompletedRun) -> GearRecord? {
        guard let id = ShoeMileage.entry(for: run, in: shoeEntries)?.gearID else { return nil }
        return gear.first { $0.gearID == id }
    }

    func loadGear() {
        gear = ((try? context.fetch(FetchDescriptor<GearRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
        shoeRuns = (try? context.fetch(FetchDescriptor<ShoeRunRecord>())) ?? []
    }

    /// Counts new runs in the default shoes. Called whenever the list of runs changes.
    func countRunsInShoes() {
        guard let shoes = defaultShoes else { return }
        let runs = ShoeMileage.runsToCount(healthRuns, entries: shoeEntries, defaultSince: shoes.since)
        guard !runs.isEmpty else { return }
        for run in runs { context.insert(ShoeRunRecord(run: run, gearID: shoes.gearID, manual: false)) }
        save()
    }

    /// The athlete picked the shoes a run was done in (nil: don't count it in any).
    func setShoes(_ shoes: GearRecord?, for run: CompletedRun) {
        let entries = shoeRuns.filter { record in
            record.runID == run.id || ShoeMileage.entry(for: run, in: [record.entry]) != nil
        }
        entries.forEach(context.delete)
        context.insert(ShoeRunRecord(run: run, gearID: shoes?.gearID, manual: true))
        save()
    }

    func addGear(_ item: GearRecord, makeDefault: Bool = false) {
        context.insert(item)
        if makeDefault, item.kind == .shoes { markDefault(item) }
        save()
        countRunsInShoes()
    }

    func saveGear(_ item: GearRecord) {
        item.updatedAt = .now
        save()
        countRunsInShoes()
    }

    func setDefaultShoes(_ shoes: GearRecord) {
        markDefault(shoes)
        save()
        countRunsInShoes()
    }

    func setRetired(_ retired: Bool, _ item: GearRecord) {
        item.retired = retired
        item.retiredAt = retired ? .now : nil
        if retired { item.isDefault = false }
        item.updatedAt = .now
        save()
    }

    /// Removes gear. Its runs stay marked as counted (in no shoes), so they don't move to the default pair.
    func deleteGear(_ item: GearRecord) {
        let id = item.gearID
        for record in shoeRuns where record.gearID == id {
            record.gearID = nil
            record.updatedAt = .now
        }
        context.delete(item)
        save()
    }

    private func markDefault(_ shoes: GearRecord) {
        for other in gear where other.isDefault && other.gearID != shoes.gearID {
            other.isDefault = false
            other.updatedAt = .now
        }
        shoes.isDefault = true
        shoes.retired = false
        shoes.updatedAt = .now
    }
}

extension AppModel {
    /// The Gear row in Settings: the default shoes and how far they've gone, or what to do first.
    var gearSummary: String {
        if let shoes = defaultShoes {
            return String(localized: "\(shoes.displayName) · \(format.distance(distance(in: shoes)))")
        }
        if !activeShoes.isEmpty { return String(localized: "\(activeShoes.count) pairs of shoes") }
        return String(localized: "Add your shoes to track how far they've gone")
    }
}
