import SwiftUI
import PlanEngine

/// Today's nudge when maximum heart rate looks out of date: a run went higher, or the watch's maximum changed since
/// the athlete set their own. They choose: update, or not now (that suggestion then stays away).
struct HeartRateSuggestionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let suggestion = model.heartRateSuggestion {
            Card {
                HStack(alignment: .top, spacing: 12) {
                    ActivityIcon(symbol: "heart.fill", colors: [Color(hex: 0xFFB3B3), Theme.red, Color(hex: 0xC23A3A)], size: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Update your heart-rate zones?").font(.headline).foregroundStyle(Theme.ink)
                        Text(message(suggestion)).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Update to \(Int(suggestion.newMax)) bpm") {
                                withAnimation { model.acceptHeartRateSuggestion(suggestion) }
                            }
                            .buttonStyle(.chip)
                            Button("Not now") { withAnimation { model.dismissHeartRateSuggestion(suggestion) } }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .transition(.opacity)
        }
    }

    private func message(_ suggestion: AppModel.HeartRateSuggestion) -> String {
        let current = Int(suggestion.current.rounded())
        switch suggestion.reason {
        case .higherInRun(let run, let bpm):
            let name = model.workout(for: run)?.name ?? String(localized: "your run")
            let day = run.date.formatted(.dateTime.weekday(.wide))
            let replacesWatch = model.heartRateSource.map { if case .watch = $0 { true } else { false } } ?? false
            let base = String(localized: "Your heart reached \(Int(bpm.rounded())) bpm on \(name) (\(day)), above your maximum of \(current). A higher maximum moves every zone up, so easy runs stay truly easy.")
            return replacesWatch ? base + " " + String(localized: "This replaces your watch's maximum in TrackStar; your watch keeps its own.") : base
        case .watchChanged(let provider):
            return String(localized: "Your watch's maximum is now \(Int(suggestion.newMax)) bpm (through \(provider)), and you're using your own \(current). Switch back to your watch's zones?")
        }
    }
}
