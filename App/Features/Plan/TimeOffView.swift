import SwiftUI
import PlanEngine

/// Opens the time-off list (from Plan, Settings, Today or the coach).
struct TimeOffRoute: Hashable {}

extension TimeOff.Reason {
    var name: String {
        switch self {
        case .vacation: String(localized: "Holiday")
        case .busy: String(localized: "Busy")
        case .injury: String(localized: "Injured")
        case .illness: String(localized: "Sick")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .vacation: "airplane"
        case .busy: "briefcase.fill"
        case .injury: "bandage.fill"
        case .illness: "thermometer.medium"
        case .other: "calendar.badge.minus"
        }
    }

    var colors: [Color] {
        switch self {
        case .vacation: [Color(hex: 0x9FE3FF), Color(hex: 0x3FB6E8), Color(hex: 0x1E87B8)]
        case .busy: [Color(hex: 0xD5D5D5), Color(hex: 0xA9A9A9), Color(hex: 0x7A7A7A)]
        case .injury: [Color(hex: 0xFFB3B3), Color(hex: 0xF26D6D), Color(hex: 0xC94545)]
        case .illness: [Color(hex: 0xFFD58A), Color(hex: 0xF5B13D), Color(hex: 0xD9861A)]
        case .other: [Color(hex: 0xCDB8FF), Color(hex: 0x9A78F0), Color(hex: 0x6F4FD0)]
        }
    }

    /// Injury and illness can be open-ended ("until I'm better").
    var canBeOpenEnded: Bool { self == .injury || self == .illness }
}

extension TimeOff {
    /// e.g. "Mon 23 Nov – Sun 29 Nov", "From Mon 23 Nov".
    var datesText: String {
        let style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        guard let end else { return String(localized: "From \(start.formatted(style))") }
        if end == start { return start.formatted(style) }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

/// Holidays, busy stretches, injuries and illness: add, change or end them, and the plan re-plans around them.
struct TimeOffView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: TimeOff?
    @State private var adding = false
    @State private var updating: PlanChangeRequest?

    var body: some View {
        let periods = model.timeOff
        let current = periods.filter { $0.contains(model.today) }
        let upcoming = periods.filter { $0.start > model.today }
        let past = periods.filter { $0.end.map { $0 < model.today } ?? false }
        List {
            Section {
                Button { adding = true } label: {
                    Label("Add time off", systemImage: "plus.circle.fill").font(.headline)
                }
            } footer: {
                Text("Going away, a busy week, injured or sick? Days off get nothing planned, the weeks around them shrink, and after a week or more off the plan eases you back in rather than picking up where it left off.")
            }
            if !current.isEmpty {
                Section("Now") {
                    ForEach(current) { period in
                        row(period)
                        Button {
                            updating = .timeOff(model.timeOffEndingToday(period))
                        } label: {
                            Label(period.reason == .injury || period.reason == .illness ? "I'm better, start again" : "I'm back early",
                                  systemImage: "figure.run")
                        }
                    }
                }
            }
            if !upcoming.isEmpty {
                Section("Coming up") { ForEach(upcoming) { row($0) } }
            }
            if !past.isEmpty {
                Section("Earlier") { ForEach(past) { row($0) } }
            }
        }
        .navigationTitle("Time off")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            TimeOffEditor(period: nil) { saved in
                updating = .timeOff(model.timeOff + [saved])
            }
        }
        .sheet(item: $editing) { period in
            TimeOffEditor(period: period, onSave: { saved in
                updating = .timeOff(model.timeOff.map { $0.id == saved.id ? saved : $0 })
            }, onDelete: {
                updating = .timeOff(model.timeOff.filter { $0.id != period.id })
            })
        }
        .fullScreenCover(item: $updating) { request in
            PlanUpdateView(request: request) { updating = nil }
        }
    }

    private func row(_ period: TimeOff) -> some View {
        Button { editing = period } label: {
            HStack(spacing: 12) {
                ActivityIcon(symbol: period.reason.symbol, colors: period.reason.colors, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(period.reason.name).font(.headline).foregroundStyle(Theme.ink)
                    Text(period.datesText + (period.mode == .easyOnly ? " · " + String(localized: "easy runs only") : ""))
                        .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Add or change one period of time off.
struct TimeOffEditor: View {
    let period: TimeOff?
    var prefill: TimeOff.Reason?
    let onSave: (TimeOff) -> Void
    var onDelete: (() -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reason: TimeOff.Reason = .vacation
    @State private var start = Date()
    @State private var end = Date()
    @State private var openEnded = false
    @State private var easyRunning = false
    @State private var loaded = false

    init(period: TimeOff?, prefill: TimeOff.Reason? = nil, onSave: @escaping (TimeOff) -> Void, onDelete: (() -> Void)? = nil) {
        self.period = period
        self.prefill = prefill
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Why") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(TimeOff.Reason.allCases, id: \.self) { option in
                            let on = reason == option
                            Button {
                                withAnimation(.snappy) { reason = option }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: option.symbol).font(.title3)
                                    Text(option.name).font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .foregroundStyle(on ? .white : Theme.ink)
                                .background(on ? Theme.accent : Theme.subtle.opacity(0.6),
                                            in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                Section {
                    DatePicker("From", selection: $start, in: firstAllowedDay..., displayedComponents: .date)
                    if reason.canBeOpenEnded {
                        Toggle("I don't know when I'll be back", isOn: $openEnded.animation())
                    }
                    if !(reason.canBeOpenEnded && openEnded) {
                        DatePicker("Until", selection: $end, in: start..., displayedComponents: .date)
                    }
                    if !reason.canBeOpenEnded {
                        Toggle("I can still do some easy running", isOn: $easyRunning)
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text(footer)
                }

                if let onDelete {
                    Section {
                        Button("Remove this time off", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(period == nil ? "Add time off" : "Time off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update plan") {
                        onSave(edited)
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
            .onChange(of: start) { _, new in if end < new { end = new } }
        }
    }

    /// Past days are history, so time off starts today at the earliest (or where an existing one already started).
    private var firstAllowedDay: Date {
        min(model.today.date(), period?.start.date() ?? model.today.date())
    }

    private var footer: String {
        switch reason {
        case .injury: String(localized: "Nothing is planned while you're injured. When you're back, the first week is easy runs only, then the plan builds up again. If running hurts, stop and see a physio or doctor; this isn't medical advice.")
        case .illness: String(localized: "Nothing is planned while you're sick, and the first few days back are easy. Rest until you feel well, especially with a fever or a chest infection.")
        default: easyRunning ? String(localized: "These days get short, easy runs only: no long run or hard sessions.")
                             : String(localized: "These days get nothing planned. After a week or more off, the plan eases you back in.")
        }
    }

    private var edited: TimeOff {
        let open = reason.canBeOpenEnded && openEnded
        return TimeOff(id: period?.id ?? UUID(), reason: reason,
                       mode: !reason.canBeOpenEnded && easyRunning ? .easyOnly : .noRunning,
                       start: LocalDate(start), end: open ? nil : LocalDate(max(end, start)))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let period {
            reason = period.reason
            start = period.start.date()
            end = period.end?.date() ?? period.start.date()
            openEnded = period.end == nil
            easyRunning = period.mode == .easyOnly
        } else {
            reason = prefill ?? .vacation
            start = model.today.date()
            end = model.today.adding(days: reason.canBeOpenEnded ? 3 : 6).date()
            openEnded = reason == .injury
        }
    }
}
