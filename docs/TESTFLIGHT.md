# TestFlight

Text to paste into App Store Connect, and the steps to get a build to testers.

## Uploading a build

1. In Xcode, pick **Any iOS Device (arm64)** as the run destination.
2. **Product › Archive.** When it finishes, the Organizer opens.
3. **Distribute App › App Store Connect › Upload.** Leave the defaults (automatic signing, upload symbols).
4. The build shows up in App Store Connect › TestFlight after 10 to 30 minutes of processing.

For every later upload, raise `CURRENT_PROJECT_VERSION` in `Config/App.xcconfig` (2, 3, …). Raise `MARKETING_VERSION`
(0.1.0 → 0.2.0) when the release is a real step forward.

## App record (once)

App Store Connect › Apps › **+** › New App:

- Platform: iOS
- Name: TrackStar (or a variation if it's taken)
- Primary language: English
- Bundle ID: `io.github.nickcia.runcoach`
- SKU: `trackstar`
- User access: Full access

## Test information (TestFlight › Test Information)

**Beta app description**

> TrackStar is a free running coach that builds a training plan for your race, from a first 5K to a marathon, and
> adapts it to the runs you actually do. It reads your runs from Apple Health, sends structured workouts to Apple
> Watch or (through Intervals.icu) to Garmin, COROS, Suunto and Wahoo, and can guide you through a run on your phone
> with spoken cues and a lock-screen display. Everything stays on your device: there are no accounts and no servers.

**Feedback email:** your email address.

**Privacy policy URL:** https://github.com/nickcia/trackstar/blob/main/PRIVACY.md

**Marketing URL (optional):** https://github.com/nickcia/trackstar

## What to test (per build)

> Thanks for trying TrackStar! This first build covers the whole app. Most useful to us:
>
> - Setting up a plan: pick a race and answer the questions. If you're new to running, try "Just starting out" for
>   the run/walk plan.
> - Today and Plan: does the plan make sense for you? Move or skip a workout and see how it adjusts.
> - Guided runs: tap Start on today's workout. Lock your phone and check the cues and the
>   lock-screen display. At the end, check the run lands in Apple Health.
> - Watches: Apple Watch gets workouts directly. For Garmin, COROS, Suunto or Wahoo, connect Intervals.icu in
>   Settings and follow the setup.
>
> Spotted something off? Take a screenshot to send feedback straight from TestFlight, or use Settings › Report a bug.

## Beta App Review (needed for external testers only)

Contact details are yours. Sign-in required: **No**.

**Review notes**

> TrackStar needs no account. To see the app with a plan, pick any race during setup.
>
> Background modes:
> - Location: only during a guided run the user starts (Start on a workout). It measures distance and
>   keeps the run going with the screen locked. We use When In Use permission with CLBackgroundActivitySession; the
>   blue location indicator shows while a run is in progress. Location is never stored off the device.
> - Audio: spoken coaching cues during a guided run (they duck the user's music).
>
> HealthKit: reads running workouts to tick off planned sessions, and writes a running workout (with distance and
> route) only when the user finishes a guided run.
>
> Live Activities: the current step and time of a guided run on the lock screen and in the Dynamic Island.
>
> Intervals.icu sign-in (Settings, optional) is a third-party service the user may already use to send workouts to
> Garmin and other watches. The app works fully without it.

## Testers

- **Internal** (people on your App Store Connect team, up to 100): no review, available as soon as the build is processed.
- **External** (anyone, by email or a public link, up to 10,000): the first build of each version goes through Beta
  App Review, usually within a day. Later builds of the same version are often approved automatically.

Builds expire after 90 days.
