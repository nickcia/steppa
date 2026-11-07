# Contributing

Thanks for your interest. This is a free app maintained in spare time, so reviews may be slow. Small,
focused pull requests are the easiest to accept.

## What's welcome

- Bug fixes, with a test that fails before the fix where possible.
- Accessibility improvements: VoiceOver, Dynamic Type, contrast.
- Translations.
- Tests, documentation, and performance improvements.
- Work on items in the README's roadmap. Please open an issue first so we can agree an approach.

## Changes to training rules

Plan rules affect people's health, so they need more than a code change:

- Explain the reasoning and link to sources (coaching literature, research).
- Update [`docs/PLAN-RULES.md`](docs/PLAN-RULES.md) to match.
- Keep `swift test` passing in `Packages/PlanEngine`, including both safety sweeps and the benchmark
  against published coaching methods ([`docs/PLAN-BENCHMARK.md`](docs/PLAN-BENCHMARK.md)). Never weaken
  `PlanValidator` or widen a benchmark range to make a change pass.
- Coaches: the benchmark doc ends with sample plans and a short questionnaire. Reviews are very welcome as
  an issue.
- Prefer conservative changes. When in doubt, the safer option wins.

## What won't be merged

These go against the project's core promises: free, private, and cheap to maintain.

- Servers, accounts, logins, or anything that sends user data off the device. The exception is a service
  the athlete chooses to connect (like Intervals.icu), talked to directly from the phone, sending only what
  that feature needs.
- Analytics, tracking or advertising SDKs.
- New third-party dependencies, unless there's a very strong reason.
- Social features, leaderboards, or shared data.
- A Strava API integration (see the README for why).
- Anything copied from other apps: names, branding, colours, illustrations, screens or text.

## Development

- Requires Xcode 26 or later. The app supports iOS 17 and later.
- Engine tests: `cd Packages/PlanEngine && swift test`
- App tests: `xcodebuild test -project Steppa.xcodeproj -scheme Steppa -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Launch with `-demo` in debug builds for sample data.
- Swift 6 with strict concurrency. App code is main-actor by default. Keep the engine free of UI and
  Apple-framework code (Foundation only).
- User-facing text should be plain, friendly and short. Use `String(localized:)` so it can be translated.

By contributing you agree that your contributions are licensed under the MIT licence. The app's name,
logo and icon remain excluded from the licence.
