import SwiftUI
import PlanEngine

/// Settings › Gear: shoes with the distance run in them, plus a watch and heart-rate monitor.
struct GearView: View {
    @Environment(AppModel.self) private var model
    @State private var adding: GearKind?
    @State private var editing: GearRecord?
    @State private var showRetired = false

    var body: some View {
        Form {
            Section {
                ForEach(model.activeShoes) { shoes in
                    Button { editing = shoes } label: { ShoeRow(shoes: shoes) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Retire") { model.setRetired(true, shoes) }.tint(Theme.secondaryInk)
                            if !shoes.isDefault {
                                Button("Default") { model.setDefaultShoes(shoes) }.tint(Theme.accent)
                            }
                        }
                }
                Button { adding = .shoes } label: { Label("Add shoes", systemImage: "plus") }
            } header: {
                Text("Shoes")
            } footer: {
                Text("Each run you do counts in your default shoes; you can change the shoes on a run's page. Most shoes are worth replacing somewhere between 500 and 800 km (300–500 mi). Lighter shoes and racing shoes wear sooner, and heavier runners or rough ground wear them faster. Take the distance as a guide: a flattened or creased midsole, worn-through tread or new aches say more than the number.")
            }

            Section {
                ForEach(model.gear.filter { $0.kind != .shoes && !$0.retired }) { item in
                    Button { editing = item } label: { DeviceRow(item: item) }
                        .buttonStyle(.plain)
                }
                Menu {
                    Button { adding = .watch } label: { Label("Watch", systemImage: GearKind.watch.symbol) }
                    Button { adding = .heartRateMonitor } label: { Label("Heart-rate monitor", systemImage: GearKind.heartRateMonitor.symbol) }
                } label: {
                    Label("Add a watch or sensor", systemImage: "plus")
                }
            } header: {
                Text("Watch and sensors")
            } footer: {
                Text("What you run with, kept with your other gear. A chest strap usually reads heart rate more steadily than a watch on the wrist, especially in intervals.")
            }

            let retired = model.gear.filter(\.retired)
            if !retired.isEmpty {
                Section("Retired") {
                    DisclosureGroup("\(retired.count) retired", isExpanded: $showRetired) {
                        ForEach(retired) { item in
                            Button { editing = item } label: {
                                if item.kind == .shoes { ShoeRow(shoes: item) } else { DeviceRow(item: item) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Gear")
        .sheet(item: $adding) { kind in
            NavigationStack { GearEditor(kind: kind, existing: nil) }
        }
        .sheet(item: $editing) { item in
            NavigationStack { GearEditor(kind: item.kind, existing: item) }
        }
    }
}

/// A pair of shoes: name, distance against the retirement distance, and a quiet bar.
struct ShoeRow: View {
    let shoes: GearRecord
    @Environment(AppModel.self) private var model

    var body: some View {
        let format = model.format
        let distance = model.distance(in: shoes)
        let wear = model.wear(of: shoes)
        HStack(spacing: 14) {
            ActivityIcon(symbol: GearKind.shoes.symbol, colors: shoes.retired ? nil : Theme.sheenColors, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(shoes.displayName.isEmpty ? String(localized: "Shoes") : shoes.displayName)
                        .font(.headline).foregroundStyle(Theme.ink)
                    if shoes.isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.subtle, in: Capsule())
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Text("\(format.distance(distance)) of \(format.distance(shoes.retireAt)) · \(shoes.shoeType.name)")
                    .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    .monospacedDigit()
                ProgressView(value: min(distance / max(shoes.retireAt, 1), 1))
                    .tint(wear == .fine ? Theme.green : wear == .nearing ? Theme.amber : Theme.red)
                if !shoes.retired, let note = ShoeAdvice.note(for: wear) {
                    Text(note).font(.caption).foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct DeviceRow: View {
    let item: GearRecord

    var body: some View {
        HStack(spacing: 14) {
            ActivityIcon(symbol: item.kind.symbol, colors: nil, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName.isEmpty ? item.kind.name : item.displayName)
                    .font(.headline).foregroundStyle(Theme.ink)
                Text("\(item.kind.name) · since \(item.since.formatted(.dateTime.month(.wide).year()))")
                    .font(.subheadline).foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// The gentle wording, shared by Gear and Today.
enum ShoeAdvice {
    static func note(for wear: ShoeWear) -> String? {
        switch wear {
        case .fine: nil
        case .nearing: String(localized: "Getting close to the usual replacement distance. Worth starting to think about the next pair.")
        case .due: String(localized: "Past the usual replacement distance. If they feel flat or the midsole is creased, it's time for a new pair.")
        }
    }
}

/// Adds or edits a pair of shoes, a watch or a heart-rate monitor.
struct GearEditor: View {
    let kind: GearKind
    let existing: GearRecord?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var shoeType: ShoeType = .daily
    @State private var since = Date.now
    @State private var starting = ""
    @State private var retireAt = ""
    @State private var makeDefault = true
    @State private var confirmDelete = false

    var body: some View {
        let units = model.units
        Form {
            Section {
                TextField(kind == .shoes ? "Model, e.g. Pegasus 41" : "Model, e.g. Forerunner 265", text: $name)
                TextField("Brand", text: $brand)
                if kind == .shoes {
                    Picker("Type", selection: $shoeType) {
                        ForEach(ShoeType.allCases) { Text($0.name).tag($0) }
                    }
                }
            }

            if kind == .shoes {
                Section {
                    DatePicker("Count runs from", selection: $since, in: ...Date.now, displayedComponents: .date)
                    LabeledContent("Earlier distance") {
                        HStack(spacing: 4) {
                            TextField("0", text: $starting).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Text(units.distanceUnit).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                } header: {
                    Text("Distance")
                } footer: {
                    Text("Runs TrackStar knows about from that day on count automatically. For shoes you've worn a while, add what you ran in them before that as earlier distance.")
                }

                Section {
                    LabeledContent("Replace at about") {
                        HStack(spacing: 4) {
                            TextField("0", text: $retireAt).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            Text(units.distanceUnit).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    if existing == nil || existing?.isDefault == false {
                        Toggle("Count new runs in these", isOn: $makeDefault)
                    }
                } footer: {
                    Text("The suggestion for a \(shoeType.name.lowercased()) is \(model.format.distance(shoeType.suggestedRetirementMeters)). Change it if your shoes last longer or wear sooner; it's a guide, not a rule.")
                }
            } else {
                Section {
                    DatePicker("Using since", selection: $since, in: ...Date.now, displayedComponents: .date)
                }
            }

            if let existing {
                Section {
                    Button(existing.retired ? "Bring back" : "Retire") {
                        model.setRetired(!existing.retired, existing)
                        dismiss()
                    }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                } footer: {
                    if kind == .shoes {
                        Text("Retired shoes keep their distance. Deleting removes them; their runs aren't counted in other shoes.")
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? String(localized: "Add \(kind.name.lowercased())") : (existing?.displayName ?? kind.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(); dismiss() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && brand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Delete this gear?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let existing { model.deleteGear(existing) }
                dismiss()
            }
        }
        .onAppear(perform: load)
        .onChange(of: shoeType) { old, new in
            // Follow the type's suggestion unless a different distance was typed.
            if retireAt.isEmpty || retireAt == Self.text(old.suggestedRetirementMeters, units: model.units, decimals: false) {
                retireAt = Self.text(new.suggestedRetirementMeters, units: model.units, decimals: false)
            }
        }
    }

    private func load() {
        let units = model.units
        if let existing {
            name = existing.name
            brand = existing.brand
            shoeType = existing.shoeType
            since = existing.since.date()
            starting = existing.startingMeters > 0 ? Self.text(existing.startingMeters, units: units, decimals: true) : ""
            retireAt = Self.text(existing.retireAt, units: units, decimals: false)
            makeDefault = existing.isDefault
        } else {
            retireAt = Self.text(shoeType.suggestedRetirementMeters, units: units, decimals: false)
            // The first pair counts runs by default; after that, ask.
            makeDefault = model.defaultShoes == nil
        }
    }

    private func save() {
        let units = model.units
        let item = existing ?? GearRecord(kind: kind, name: "", since: LocalDate(since))
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.brand = brand.trimmingCharacters(in: .whitespaces)
        item.since = LocalDate(since)
        if kind == .shoes {
            item.shoeType = shoeType
            item.startingMeters = Self.meters(starting, units: units) ?? 0
            let typed = Self.meters(retireAt, units: units)
            // Keep following the type's suggestion unless a different number was typed.
            item.retirementMeters = typed.flatMap { abs($0 - shoeType.suggestedRetirementMeters) < units.metersPerUnit ? nil : $0 }
        }
        if let existing {
            if kind == .shoes, makeDefault, !existing.isDefault { model.setDefaultShoes(existing) }
            model.saveGear(existing)
        } else {
            model.addGear(item, makeDefault: kind == .shoes && makeDefault)
        }
    }

    static func text(_ meters: Double, units: UnitSystem, decimals: Bool) -> String {
        let value = meters / units.metersPerUnit
        return decimals ? value.formatted(.number.precision(.fractionLength(0...1))) : "\(Int(value.rounded()))"
    }

    static func meters(_ text: String, units: UnitSystem) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return value * units.metersPerUnit
    }
}

/// On Today, once per pair: these shoes are near or past their replacement distance.
struct ShoeReplacementNudge: View {
    @Environment(AppModel.self) private var model
    /// IDs of shoes whose suggestion was dismissed, comma-separated.
    @AppStorage("gear.dismissedShoeNudges") private var dismissed = ""
    @State private var showingGear = false

    var body: some View {
        let dismissedIDs = Set(dismissed.split(separator: ",").map(String.init))
        if let shoes = model.shoesToReplace.first(where: { !dismissedIDs.contains($0.gearID.uuidString) }) {
            let wear = model.wear(of: shoes)
            Card {
                HStack(alignment: .top, spacing: 12) {
                    ActivityIcon(symbol: GearKind.shoes.symbol, colors: Theme.sheenColors, size: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(wear == .due ? "Time to look at new shoes?" : "Your shoes are getting there")
                            .font(.headline).foregroundStyle(Theme.ink)
                        Text("\(shoes.displayName) have \(model.format.distance(model.distance(in: shoes))) on them. \(ShoeAdvice.note(for: wear) ?? "")")
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("See gear") { showingGear = true }.buttonStyle(.chip)
                            Button("Not now") {
                                withAnimation { dismissed = (dismissedIDs.union([shoes.gearID.uuidString])).sorted().joined(separator: ",") }
                            }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .sheet(isPresented: $showingGear) {
                NavigationStack {
                    GearView().toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showingGear = false } }
                    }
                }
            }
        }
    }
}

/// On a run's page: which shoes it was done in, and a menu to change them.
struct RunShoesRow: View {
    let run: CompletedRun
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.shoes.isEmpty {
            let current = model.shoes(for: run)
            Menu {
                ForEach(model.shoes.filter { !$0.retired || $0.gearID == current?.gearID }) { shoes in
                    Button {
                        model.setShoes(shoes, for: run)
                    } label: {
                        if shoes.gearID == current?.gearID {
                            Label(shoes.displayName, systemImage: "checkmark")
                        } else {
                            Text(shoes.displayName)
                        }
                    }
                }
                Divider()
                Button("No shoes counted") { model.setShoes(nil, for: run) }
            } label: {
                Card(padding: 16) {
                    HStack(spacing: 12) {
                        ActivityIcon(symbol: GearKind.shoes.symbol, colors: current == nil ? nil : Theme.sheenColors, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shoes").font(.caption).foregroundStyle(Theme.secondaryInk)
                            Text(current?.displayName ?? String(localized: "Not counted in any shoes"))
                                .font(.headline).foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
