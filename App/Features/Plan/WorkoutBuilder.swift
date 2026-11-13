import SwiftUI
import PlanEngine

// Custom workouts: the athlete builds a workout from blocks (warm-up, zone runs, repeats, cool-down), with paces
// filled in from their fitness, puts it on a day and keeps it in "My workouts" to reuse.

// MARK: - Labels

extension Effort {
    /// "Zone 2 · Easy"
    var label: String {
        switch self {
        case .recovery: String(localized: "Zone 1 · Recovery")
        case .easy: String(localized: "Zone 2 · Easy")
        case .steady: String(localized: "Zone 3 · Steady")
        case .threshold: String(localized: "Zone 4 · Threshold")
        case .vo2max: String(localized: "Zone 5 · VO₂max")
        case .speed: String(localized: "Speed")
        case .racePace: String(localized: "Race pace")
        case .open: String(localized: "No target")
        }
    }

    /// "Zone 2", for block titles.
    var shortLabel: String {
        zoneNumber.map { String(localized: "Zone \($0)") } ?? label
    }

    var hint: String {
        switch self {
        case .recovery: String(localized: "Slower than easy. For jogs between repeats and very easy days.")
        case .easy: String(localized: "Conversational. You could talk in full sentences.")
        case .steady: String(localized: "Your marathon pace. Steady and controlled.")
        case .threshold: String(localized: "Comfortably hard, a pace you could hold for about an hour.")
        case .vo2max: String(localized: "Hard. For efforts of 2 to 5 minutes.")
        case .speed: String(localized: "Fast but relaxed, for short reps and strides.")
        case .racePace: String(localized: "Your predicted pace for your goal race.")
        case .open: String(localized: "Run by feel, or walk. No pace alerts.")
        }
    }

    var color: Color {
        switch self {
        case .recovery: WorkoutKind.easy.color.opacity(0.5)
        case .open: Theme.subtle
        default: paceZone?.color ?? Theme.subtle
        }
    }
}

extension WorkoutBlock.Preset {
    var title: String {
        switch self {
        case .warmup: String(localized: "Warm up")
        case .easy: String(localized: "Zone 2")
        case .steady: String(localized: "Steady")
        case .tempo: String(localized: "Tempo")
        case .intervals: String(localized: "Intervals")
        case .strides: String(localized: "Strides")
        case .cooldown: String(localized: "Cool down")
        case .recovery: String(localized: "Zone 1 recovery")
        case .racePace: String(localized: "Race pace")
        case .open: String(localized: "No target")
        }
    }

    /// The buttons always on show; the rest sit under More.
    static let main: [Self] = [.warmup, .easy, .tempo, .intervals, .cooldown]
    static let more: [Self] = [.recovery, .steady, .strides, .racePace, .open]
}

extension WorkoutBlock {
    var title: String {
        switch role {
        case .warmup: String(localized: "Warm up")
        case .cooldown: String(localized: "Cool down")
        case .run: main.effort.label
        case .repeats: String(localized: "\(repeats) × \(main.effort.shortLabel)")
        }
    }
}

extension DisplayFormat {
    /// "10 min", "45 s", "1:30 min", "2 km", "400 m".
    func length(_ goal: StepGoal) -> String {
        switch goal {
        case .time(let seconds): seconds < 60 ? "\(Int(seconds)) s" : DisplayFormat.minutes(seconds)
        case .distance(let meters): repDistance(meters)
        }
    }

    /// "10 min · 6:20–6:58 /km", "10 min · by feel".
    func part(_ part: BlockPart, paces: PaceTable) -> String {
        let pace = part.pace(paces).map(paceRange) ?? String(localized: "by feel")
        return "\(length(part.length)) · \(pace)"
    }
}

// MARK: - Builder

/// Builds or edits a custom workout block by block.
struct WorkoutBuilderView: View {
    enum Purpose: Equatable {
        /// A new workout for this day.
        case add(LocalDate)
        /// A custom workout already on a day.
        case editDay(Workout)
        /// A workout in My workouts.
        case editSaved
    }

    let purpose: Purpose
    /// Called once the workout is added or saved.
    var onFinish: () -> Void = {}
    @State var template: WorkoutTemplate
    @Environment(AppModel.self) private var model
    @State private var editing: WorkoutBlock?
    @State private var keepInLibrary = true

    init(purpose: Purpose, template: WorkoutTemplate = WorkoutTemplate(name: "", blocks: []), onFinish: @escaping () -> Void = {}) {
        self.purpose = purpose
        self.onFinish = onFinish
        _template = State(initialValue: template)
    }

    var body: some View {
        let paces = model.plan?.paces
        List {
            Section {
                TextField("Workout name", text: $template.name)
                    .font(.title3.weight(.semibold))
                if let paces, !template.blocks.isEmpty {
                    WorkoutSummaryStrip(template: template, paces: paces)
                }
            }
            Section {
                if template.blocks.isEmpty {
                    Text("Add blocks below. Paces come from your fitness, and you can change any of them.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                ForEach(template.blocks) { block in
                    Button { editing = block } label: {
                        BlockRow(block: block, paces: paces)
                    }
                    .buttonStyle(.plain)
                }
                .onMove { template.blocks.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { template.blocks.remove(atOffsets: $0) }
            } header: {
                if !template.blocks.isEmpty { Text("Blocks") }
            } footer: {
                if template.blocks.count > 1 { Text("Hold and drag to reorder. Swipe to remove.") }
            }
            Section("Add a block") {
                AddBlockButtons { template.blocks.append(.preset($0)) }
            }
            if showsLibraryToggle {
                Section {
                    Toggle("Save to My workouts", isOn: $keepInLibrary)
                } footer: {
                    Text("Reuse it on any day from the calendar.")
                }
            }
        }
        .animation(.snappy, value: template.blocks)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { finishButton }
        .sheet(item: $editing) { block in
            if let paces {
                BlockEditorView(block: block, paces: paces) { updated in
                    replace(block.id, with: updated)
                }
            }
        }
        .onAppear {
            if case .editDay = purpose { keepInLibrary = isInLibrary }
        }
    }

    private var navigationTitle: String {
        switch purpose {
        case .add: String(localized: "New workout")
        case .editDay, .editSaved: String(localized: "Edit workout")
        }
    }

    private var isInLibrary: Bool { model.savedWorkouts.contains { $0.id == template.id } }

    /// Adding to a day can also save it; editing a day's workout can update the saved copy.
    private var showsLibraryToggle: Bool {
        switch purpose {
        case .add: true
        case .editDay: isInLibrary
        case .editSaved: false
        }
    }

    private var finishTitle: String {
        switch purpose {
        case .add(let date): String(localized: "Add to \(date.shortDayMonth)")
        case .editDay, .editSaved: String(localized: "Save")
        }
    }

    private var finishButton: some View {
        Button(finishTitle) { finish() }
            .buttonStyle(.primary)
            .disabled(template.blocks.isEmpty)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(.bar)
    }

    private func replace(_ id: WorkoutBlock.ID, with block: WorkoutBlock?) {
        guard let index = template.blocks.firstIndex(where: { $0.id == id }) else { return }
        if let block { template.blocks[index] = block } else { template.blocks.remove(at: index) }
    }

    private func finish() {
        var finished = template
        finished.name = finished.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if finished.name.isEmpty { finished.name = String(localized: "My workout") }
        switch purpose {
        case .add(let date):
            if keepInLibrary { model.saveWorkout(finished) }
            model.addWorkout(finished, on: date)
        case .editDay(let workout):
            if keepInLibrary, isInLibrary { model.saveWorkout(finished) }
            model.updateWorkout(workout, to: finished)
        case .editSaved:
            model.saveWorkout(finished)
        }
        onFinish()
    }
}

/// Total time and distance, and the workout's shape as coloured bars (taller is harder).
private struct WorkoutSummaryStrip: View {
    let template: WorkoutTemplate
    let paces: PaceTable
    @Environment(AppModel.self) private var model

    var body: some View {
        let workout = template.workout(on: model.today, id: "preview", paces: paces)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.Spacing.l) {
                Metric(value: "~\(DisplayFormat.shortDuration(workout.totalSeconds))", label: String(localized: "time"))
                Metric(value: "~\(model.format.distance(workout.totalMeters))", label: String(localized: "distance"))
            }
            WorkoutShapeView(workout: workout, height: 44)
        }
        .padding(.vertical, 4)
    }

}

private struct BlockRow: View {
    let block: WorkoutBlock
    let paces: PaceTable?
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(block.main.effort.color)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if let paces {
                    Text(model.format.part(block.main, paces: paces))
                        .font(.caption).monospacedDigit().foregroundStyle(Theme.secondaryInk)
                    if block.role == .repeats, let recovery = block.recovery {
                        Text(String(localized: "then \(model.format.part(recovery, paces: paces))"))
                            .font(.caption).monospacedDigit().foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
            Spacer(minLength: 0)
            if block.main.customPace != nil {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                    .accessibilityLabel("Your own pace")
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// The main block types as tiles, the rest in a menu. Each tile shows its zone's colour.
private struct AddBlockButtons: View {
    let add: (WorkoutBlock.Preset) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(WorkoutBlock.Preset.main, id: \.self) { preset in
                Button { add(preset) } label: {
                    tile(preset.title, color: WorkoutBlock.preset(preset).main.effort.color)
                }
                .buttonStyle(.plain)
            }
            Menu {
                ForEach(WorkoutBlock.Preset.more, id: \.self) { preset in
                    Button(preset.title) { add(preset) }
                }
            } label: {
                tile(String(localized: "More…"), color: nil)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func tile(_ title: String, color: Color?) -> some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Theme.subtle.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Block editor

/// Edits one block: its effort, length and pace, and for repeats, how many and the recovery between.
struct BlockEditorView: View {
    let paces: PaceTable
    let onDone: (WorkoutBlock?) -> Void
    @State private var block: WorkoutBlock
    @Environment(\.dismiss) private var dismiss

    init(block: WorkoutBlock, paces: PaceTable, onDone: @escaping (WorkoutBlock?) -> Void) {
        self.paces = paces
        self.onDone = onDone
        _block = State(initialValue: block)
    }

    var body: some View {
        NavigationStack {
            Form {
                if block.role == .repeats {
                    Section {
                        Stepper(value: $block.repeats, in: 1...40) {
                            Text("\(block.repeats) repeats").font(.headline)
                        }
                    }
                }
                PartEditor(title: block.role == .repeats ? String(localized: "Each repeat") : nil,
                           part: $block.main, paces: paces)
                if block.role == .repeats {
                    recoverySection
                }
                Section {
                    Button("Remove block", role: .destructive) {
                        onDone(nil)
                        dismiss()
                    }
                }
            }
            .navigationTitle(block.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(block)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var recoverySection: some View {
        Section {
            Toggle("Recovery between repeats", isOn: Binding(
                get: { block.recovery != nil },
                set: { block.recovery = $0 ? BlockPart(effort: .recovery, length: .time(seconds: 90)) : nil }))
        }
        if block.recovery != nil {
            PartEditor(title: String(localized: "Recovery"), part: Binding(
                get: { block.recovery ?? BlockPart(effort: .recovery, length: .time(seconds: 90)) },
                set: { block.recovery = $0 }), paces: paces)
        }
    }
}

/// Effort, length and pace for one part of a block.
private struct PartEditor: View {
    let title: String?
    @Binding var part: BlockPart
    let paces: PaceTable
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Picker("Effort", selection: effortBinding) {
                ForEach(Effort.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text(part.effort.hint).font(.caption).foregroundStyle(Theme.secondaryInk)
        } header: {
            if let title { Text(title) }
        }
        Section("Length") {
            LengthEditor(length: $part.length, units: model.units)
        }
        if part.effort != .open {
            PaceEditor(part: $part, paces: paces, format: model.format)
        }
    }

    /// A new effort brings its own pace back.
    private var effortBinding: Binding<Effort> {
        Binding(get: { part.effort }, set: { part.effort = $0; part.customPace = nil })
    }
}

/// Time (minutes and seconds) or distance (in the athlete's units), on wheels.
private struct LengthEditor: View {
    @Binding var length: StepGoal
    let units: UnitSystem

    private enum Mode: Hashable { case time, distance }

    var body: some View {
        Picker("Measure by", selection: modeBinding) {
            Text("Time").tag(Mode.time)
            Text("Distance").tag(Mode.distance)
        }
        .pickerStyle(.segmented)
        switch length {
        case .time: timeWheels
        case .distance: distanceWheels
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(get: {
            if case .time = length { return .time }
            return .distance
        }, set: { mode in
            switch mode {
            case .time: length = .time(seconds: 10 * 60)
            case .distance: length = .distance(meters: units.metersPerUnit)
            }
        })
    }

    private var seconds: Double {
        if case .time(let s) = length { return s }
        return 0
    }

    private var timeWheels: some View {
        HStack(spacing: 0) {
            Picker("Minutes", selection: Binding(get: { Int(seconds) / 60 }, set: { setTime(minutes: $0, seconds: Int(seconds) % 60) })) {
                ForEach(0...180, id: \.self) { Text("\($0) min").tag($0) }
            }
            Picker("Seconds", selection: Binding(get: { Int(seconds) % 60 / 5 * 5 }, set: { setTime(minutes: Int(seconds) / 60, seconds: $0) })) {
                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { Text("\($0) s").tag($0) }
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 130)
    }

    private func setTime(minutes: Int, seconds: Int) {
        // Never zero: a block needs some length.
        length = .time(seconds: Double(max(5, minutes * 60 + seconds)))
    }

    /// Hundredths of a unit, in steps of 0.05 (e.g. 0.40 km, 0.25 mi).
    private var hundredths: Int {
        if case .distance(let m) = length { return Int((m / units.metersPerUnit * 20).rounded()) * 5 }
        return 0
    }

    private var distanceWheels: some View {
        HStack(spacing: 0) {
            Picker("Whole", selection: Binding(get: { hundredths / 100 }, set: { setDistance($0 * 100 + hundredths % 100) })) {
                ForEach(0...50, id: \.self) { Text("\($0)").tag($0) }
            }
            Picker("Fraction", selection: Binding(get: { hundredths % 100 }, set: { setDistance(hundredths / 100 * 100 + $0) })) {
                ForEach(Array(stride(from: 0, through: 95, by: 5)), id: \.self) { Text(String(format: ".%02d", $0)).tag($0) }
            }
            Text(units.distanceUnit).font(.headline).padding(.trailing, 24)
        }
        .pickerStyle(.wheel)
        .frame(height: 130)
    }

    private func setDistance(_ hundredths: Int) {
        length = .distance(meters: Double(max(5, hundredths)) / 100 * units.metersPerUnit)
    }
}

/// The effort's own pace from the athlete's fitness, or a pace band of their own.
private struct PaceEditor: View {
    @Binding var part: BlockPart
    let paces: PaceTable
    let format: DisplayFormat

    /// 5 seconds per km or mile, in s/km.
    private var nudge: Double { 5 / format.units.metersPerUnit * 1000 }

    var body: some View {
        Section {
            Toggle("Use my zone pace", isOn: Binding(
                get: { part.customPace == nil },
                set: { part.customPace = $0 ? nil : part.effort.pace(paces) }))
            if let own = part.customPace {
                Stepper(value: Binding(get: { own.fast }, set: { setFast($0) }), step: nudge) {
                    LabeledContent("Fastest", value: format.pace(own.fast))
                }
                Stepper(value: Binding(get: { own.slow }, set: { setSlow($0) }), step: nudge) {
                    LabeledContent("Slowest", value: format.pace(own.slow))
                }
            } else if let auto = part.effort.pace(paces) {
                LabeledContent("Pace", value: format.paceRange(auto)).monospacedDigit()
            }
        } header: {
            Text("Pace")
        } footer: {
            Text(part.customPace == nil
                 ? "Worked out from your fitness, and kept up to date as it changes."
                 : "Your own pace stays as you set it.")
        }
    }

    private func setFast(_ value: Double) {
        guard var own = part.customPace else { return }
        own.fast = min(max(120, value), own.slow)
        part.customPace = own
    }

    private func setSlow(_ value: Double) {
        guard var own = part.customPace else { return }
        own.slow = max(min(1200, value), own.fast)
        part.customPace = own
    }
}

// MARK: - Adding to a day

/// Picks a saved workout for a day, or starts a new one.
struct AddWorkoutSheet: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var building = false

    var body: some View {
        NavigationStack {
            List {
                if let planned = model.plannedWorkout(on: date) {
                    Section {
                        Label(String(localized: "Replaces your \(planned.kind.casualName) (\(WorkoutDescriber(format: model.format).summary(planned))). Remove yours later to bring it back."),
                              systemImage: "arrow.triangle.swap")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Section {
                    Button { building = true } label: {
                        Label("Build a new workout", systemImage: "plus.square.on.square")
                            .font(.headline)
                    }
                }
                Section {
                    if model.savedWorkouts.isEmpty {
                        Text("Workouts you build are kept here, to add to any day.")
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                    ForEach(model.savedWorkouts) { template in
                        SavedWorkoutRow(template: template) {
                            model.addWorkout(template, on: date)
                            dismiss()
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { model.savedWorkouts[$0] }.forEach(model.deleteSavedWorkout)
                    }
                } header: {
                    Text("My workouts")
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(isPresented: $building) {
                WorkoutBuilderView(purpose: .add(date)) { dismiss() }
            }
        }
    }
}

/// A saved workout: tap to use it; Edit opens the builder.
private struct SavedWorkoutRow: View {
    let template: WorkoutTemplate
    let use: () -> Void
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: use) {
                HStack(spacing: 12) {
                    KindIcon(kind: .custom, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text(summary).font(.caption).foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Edit") { editing = true }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                WorkoutBuilderView(purpose: .editSaved, template: template) { editing = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                    }
            }
        }
    }

    private var summary: String {
        guard let paces = model.plan?.paces else { return "" }
        let workout = template.workout(on: model.today, id: "preview", paces: paces)
        return "\(template.blocks.count) blocks · \(WorkoutDescriber(format: model.format).summary(workout))"
    }
}

// MARK: - On a custom workout's page

/// Edit, copy to another day, save to My workouts, or remove: shown on a custom workout's detail page.
struct CustomWorkoutActions: View {
    let workout: Workout
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var copying = false
    @State private var confirmingRemove = false

    var body: some View {
        if let scheduled = model.scheduled(workout) {
            VStack(spacing: Theme.Spacing.s) {
                if workout.date >= model.today {
                    Button { editing = true } label: { Label("Edit workout", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.secondary)
                }
                HStack(spacing: Theme.Spacing.l) {
                    Button { copying = true } label: { Label("Add to another day", systemImage: "plus.square.on.square") }
                    if !model.savedWorkouts.contains(where: { $0.id == scheduled.template.id }) {
                        Button { model.saveWorkout(scheduled.template) } label: { Label("Save", systemImage: "bookmark") }
                    }
                }
                .font(.subheadline.weight(.semibold))
                Button(role: .destructive) { confirmingRemove = true } label: {
                    Text(model.plannedWorkout(on: workout.date) == nil ? "Remove workout" : "Remove and bring back the plan's run")
                }
                .font(.subheadline)
                .padding(.top, Theme.Spacing.xs)
            }
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $editing) {
                NavigationStack {
                    WorkoutBuilderView(purpose: .editDay(workout), template: scheduled.template) { editing = false }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                        }
                }
            }
            .sheet(isPresented: $copying) {
                CopyWorkoutSheet(template: scheduled.template, from: workout.date)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Remove this workout?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.removeWorkout(workout)
                    dismiss()
                }
            } message: {
                Text("It stays in My workouts if you saved it.")
            }
        }
    }
}

/// Picks another day for a copy of a custom workout.
private struct CopyWorkoutSheet: View {
    let template: WorkoutTemplate
    let from: LocalDate
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now

    var body: some View {
        let day = LocalDate(date)
        NavigationStack {
            Form {
                DatePicker("Day", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                if let planned = model.plannedWorkout(on: day), model.canAddWorkout(on: day) {
                    Text(String(localized: "Replaces your \(planned.kind.casualName) that day."))
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
            }
            .navigationTitle("Add to another day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        model.addWorkout(template, on: day)
                        dismiss()
                    }
                    .disabled(!model.canAddWorkout(on: day) || day == from)
                }
            }
        }
        .onAppear { date = from.adding(days: 7).date() }
    }

    private var range: ClosedRange<Date> {
        let start = model.today.date()
        let end = (model.plan?.inputs.raceDate.adding(days: -1) ?? model.today).date()
        return start...max(start, end)
    }
}
