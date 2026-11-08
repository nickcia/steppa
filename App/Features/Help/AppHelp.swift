import Foundation

/// How to do things in the app: the Help screen in Settings shows these, and the coach looks them up to answer
/// "how do I…?" questions (so it never guesses at menu names).
nonisolated struct HelpArticle: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Extra words people use for this, for search ("garmin", "forerunner", "fenix"…).
    let keywords: [String]
    let body: String
}

nonisolated enum AppHelp {
    static let articles: [HelpArticle] = [
        HelpArticle(id: "garmin", title: "Connect a Garmin, COROS, Suunto or Wahoo watch",
                    keywords: ["garmin", "coros", "suunto", "wahoo", "forerunner", "fenix", "epix", "instinct", "polar", "watch", "connect", "sync", "intervals", "send workouts"],
                    body: """
                    TrackStar sends workouts to these watches through Intervals.icu, a free training site, because Garmin doesn't let small apps connect directly.
                    1. In TrackStar, go to Settings › Other watches and tap Connect Garmin, COROS and others. Sign in to Intervals.icu (or create a free account).
                    2. On intervals.icu, open Settings › Connections and connect your Garmin (or COROS, Suunto, Wahoo). Allow it to upload planned workouts and download activities.
                    3. Back in TrackStar, Settings › Other watches shows your watch as Receiving. Your upcoming workouts appear in Garmin Connect's calendar and on your watch, and finished runs come back to TrackStar automatically.
                    Your watch's heart-rate zones come across too (Settings › Heart-rate zones).
                    """),
        HelpArticle(id: "applewatch", title: "Send workouts to Apple Watch",
                    keywords: ["apple watch", "watch", "workout app", "send", "pace alerts"],
                    body: """
                    Open a workout (or today's card) and tap Send to Apple Watch. It appears in the Workout app with every step and pace alerts. To send workouts automatically, turn on Settings › Apple Watch › Send the next 7 days automatically. Runs you record on the watch tick workouts off through Apple Health.
                    """),
        HelpArticle(id: "health", title: "Connect Apple Health so runs tick off",
                    keywords: ["health", "apple health", "runs not showing", "missing run", "tick off", "strava", "sync runs", "import"],
                    body: """
                    Settings › Apple Health › Connect Apple Health. TrackStar reads your running workouts (from Apple Watch, Garmin Connect, COROS, Strava and other apps that save to Health) and ticks off the matching workouts. If a run is missing, check the Health app under Sharing › Apps › TrackStar, then tap Refresh runs in Settings. You can also tick a workout off by hand with Mark as done.
                    """),
        HelpArticle(id: "timeoff", title: "Plan a holiday, a busy week or time off",
                    keywords: ["vacation", "holiday", "trip", "travel", "away", "break", "busy", "time off", "can't run", "cannot run", "days off", "pause"],
                    body: """
                    Tap the plane button at the top of the Plan tab (or Settings › Time off and injuries), then Add time off. Pick why (holiday, busy, other), the dates, and whether you can still do some easy running. TrackStar clears those days, shrinks those weeks, and after a week or more off restarts a little lower and builds back up. To come back early, tap I'm back early on Today.
                    """),
        HelpArticle(id: "injury", title: "I'm injured or sick",
                    keywords: ["injured", "injury", "hurt", "pain", "sick", "ill", "illness", "cold", "flu", "covid", "rest", "physio"],
                    body: """
                    Tap the plane button on the Plan tab (or Settings › Time off and injuries) › Add time off, and choose Injured or Sick. If you don't know when you'll be better, switch on I don't know when I'll be back: the plan pauses. When you can run again, tap I'm better on Today: the first week back is easy runs only, then the plan builds up again. If running hurts, or you have chest pain, dizziness or a fever, rest and see a doctor or physio.
                    """),
        HelpArticle(id: "heartrate", title: "Run by heart rate, and heart-rate zones",
                    keywords: ["heart rate", "hr", "bpm", "zones", "zone 2", "pulse", "max heart rate", "import zones"],
                    body: """
                    Open a workout and switch the Structure card to Heart rate: each step shows its zone and beats per minute (easy runs are zone 2, threshold zone 4, intervals zone 5). To show heart rate everywhere, Settings › Heart rate and treadmill › Show targets as › Heart rate. Zones come from your Garmin or other watch through Intervals.icu, or set your own in Settings › Heart-rate zones; otherwise they're estimated from your maximum heart rate (Settings › Apple Health › Max heart rate). Apple Watch doesn't share its zones with apps.
                    """),
        HelpArticle(id: "treadmill", title: "Treadmill speeds in km/h or mph",
                    keywords: ["treadmill", "km/h", "kmh", "mph", "speed", "indoor", "gym", "incline"],
                    body: """
                    Open a workout and switch the Structure card to Treadmill: paces become treadmill speeds. Use the km/h / mph switch next to it to match your treadmill (this is separate from km or miles for distance). You can also set it in Settings › Heart rate and treadmill › Treadmill speed. Many runners set a 1% incline to match running outside.
                    """),
        HelpArticle(id: "units", title: "Kilometres or miles",
                    keywords: ["miles", "kilometres", "kilometers", "km", "mi", "units", "imperial", "metric", "pace per mile"],
                    body: """
                    Settings › Units: Kilometres or Miles. Distances and paces change everywhere. Treadmill speed (km/h or mph) has its own setting.
                    """),
        HelpArticle(id: "rundays", title: "Change your run days or long-run day",
                    keywords: ["run days", "days", "schedule", "long run day", "weekday", "availability", "change days"],
                    body: """
                    Settings › Training › Run days. Pick your days and long-run day, then Update plan: workouts from today on move to the new days. If your goal usually needs more days than you've picked, TrackStar tells you.
                    """),
        HelpArticle(id: "race", title: "Change the race date or goal time, or add a race",
                    keywords: ["race", "race date", "goal", "goal time", "tune-up", "result", "marathon", "half marathon", "10k", "5k", "new race"],
                    body: """
                    Settings › Races (or tap the Race day tile on Today). Change date and Edit goal are on the goal race card. Use + to add a tune-up race or a past result; a recent result can update your training paces.
                    """),
        HelpArticle(id: "move", title: "Move or skip a workout",
                    keywords: ["move", "swap", "reschedule", "skip", "change day", "another day"],
                    body: """
                    On Today's card or a workout's screen, tap Move (the arrows) to pick another day in the same week; the plan won't put two hard days in a row. Tap Skip to skip it. Skipped and missed runs aren't made up: the plan adjusts from what you actually did.
                    """),
        HelpArticle(id: "strength", title: "Strength sessions",
                    keywords: ["strength", "gym", "weights", "core", "bodyweight", "exercises"],
                    body: """
                    Settings › Strength › Strength sessions, with 1 or 2 a week. Short bodyweight routines appear on Today and in the Plan tab, away from your key runs.
                    """),
        HelpArticle(id: "calendar", title: "Add workouts to your calendar",
                    keywords: ["calendar", "google calendar", "outlook", "schedule", "add to calendar", "ical"],
                    body: """
                    Tap Add to Calendar on a workout for one event, or turn on Settings › Calendar › Show my plan in Calendar to keep your whole plan in its own calendar, updated as the plan changes.
                    """),
        HelpArticle(id: "recap", title: "Run analysis, recaps and sharing a run",
                    keywords: ["analysis", "recap", "splits", "share", "strava", "instagram", "image", "run details", "heart rate chart"],
                    body: """
                    Open a run from Today, the Progress tab or a ticked-off workout. You'll see splits, pace and heart-rate charts and time in zones. Analyse this run (iOS 26 and later with Apple Intelligence) writes a recap. The share button makes an image for Strava, Instagram or a message.
                    """),
        HelpArticle(id: "coach", title: "The coach and Apple Intelligence",
                    keywords: ["coach", "ai", "apple intelligence", "chat", "assistant", "ios 26"],
                    body: """
                    The coach runs on your iPhone with Apple Intelligence (iPhone 15 Pro or later, iOS 26 or later, Apple Intelligence turned on). Nothing leaves your phone. Turn it on or off in Settings › Coach › Show the coach.
                    """),
        HelpArticle(id: "bug", title: "Report a bug",
                    keywords: ["bug", "problem", "crash", "report", "feedback", "support", "contact", "email"],
                    body: """
                    Settings › About › Report a bug opens your email app with a report ready to send (app version, phone, and a short plan summary). If TrackStar crashed, it offers to send the crash report next time it opens.
                    """),
        HelpArticle(id: "export", title: "Back up, move to a new phone, or start a new plan",
                    keywords: ["export", "backup", "back up", "import", "new phone", "transfer", "end plan", "new plan", "start over", "reset"],
                    body: """
                    With iCloud on, your plan follows you to a new iPhone. You can also save everything as a file with Settings › Your data › Export data, and bring it back with Import data. To start a new plan, Settings › Training › End this plan, then answer the questions again.
                    """),
        HelpArticle(id: "reminders", title: "Workout reminders",
                    keywords: ["reminder", "notification", "notify", "alert", "morning"],
                    body: """
                    Settings › Reminders › Workout reminders: a notification on run days at the time you choose.
                    """),
    ]

    /// The best-matching articles for a question, best first. Matches words in the title, keywords and text, with
    /// title and keyword matches counting most.
    static func search(_ query: String, limit: Int = 3) -> [HelpArticle] {
        let q = query.lowercased()
        let words = q.split { !$0.isLetter && !$0.isNumber && $0 != "/" }.map(String.init).filter { $0.count > 2 && !stopWords.contains($0) }
        guard !words.isEmpty || !q.isEmpty else { return [] }
        let scored = articles.map { article -> (HelpArticle, Int) in
            let title = article.title.lowercased(), body = article.body.lowercased()
            var score = 0
            for keyword in article.keywords where q.contains(keyword) { score += keyword.contains(" ") ? 6 : 4 }
            for word in words {
                if title.contains(word) { score += 3 }
                if article.keywords.contains(where: { $0.hasPrefix(word) }) { score += 2 }
                if body.contains(word) { score += 1 }
            }
            return (article, score)
        }
        return scored.filter { $0.1 >= 3 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private static let stopWords: Set<String> = ["how", "the", "can", "and", "for", "you", "your", "what", "does", "with",
                                                 "app", "trackstar", "set", "use", "get", "into", "this", "that", "want"]
}
