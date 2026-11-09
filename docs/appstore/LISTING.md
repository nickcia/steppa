# App Store listing

Everything App Store Connect asks for on the app's version page and App Information, ready to paste.
Character limits are Apple's.

## Screenshots

`docs/appstore/screenshots/` has six 6.9-inch screenshots (1320 × 2868), in order. Upload them to the
**iPhone 6.9" Display** slot; App Store Connect scales them down for smaller iPhones.

They're captured from the debug build's demo data on an iPhone 18 Pro Max simulator. To retake them after
the app changes, launch with `-demo` plus:

| # | Screen | Launch options |
|---|--------|----------------|
| 1 | Today, with a run | `-day 1` |
| 2 | Workout detail | `-open workout` |
| 3 | Guided run | `-guidedRun`, with a simulated route (`xcrun simctl location … start`) and location allowed |
| 4 | Plan | `-tab plan` |
| 5 | Run analysis | `-open run` |
| 6 | Progress | `-tab progress` |

## App Information

- **Name** (30): `TrackStar: Running Coach`
  If it's taken: `TrackStar Run Coach` or `TrackStar – Race Training`.
- **Subtitle** (30): `Free plans for your next race`
- **Primary category:** Health & Fitness
- **Secondary category:** Sports
- **Content rights:** No third-party content.
- **Age rating:** answer "None" / "No" to everything → 4+.

## Version page

**Promotional text** (170, can change any time without review)

> A free running coach that builds your plan around your race, adapts it to the runs you actually do, and
> keeps everything on your phone.

**Description** (4,000)

> TrackStar builds a training plan for your race and adapts it as you go, from a first 5K to a marathon. It's free,
> it has no ads or subscriptions, and your data never leaves your phone.
>
> A PLAN THAT FITS YOUR LIFE
> • Pick your race and date, the days you can run and how much you run now. TrackStar builds week-by-week training
>   with base, build, peak and taper phases.
> • Easy runs, long runs, tempo, intervals, hills and strides, each with target paces worked out from your fitness.
> • New to running? Start with a run/walk plan that builds to 30 minutes non-stop before the real training begins.
> • Strength sessions for runners, with no equipment needed.
>
> ADAPTS AS YOU TRAIN
> • Runs from Apple Health tick off your workouts automatically, including runs from Apple Watch, Garmin, COROS and
>   other apps that sync to Health.
> • Move or skip a workout, or take time off for illness, travel or injury, and the rest of the plan adjusts safely.
> • A race-time prediction that updates as your fitness changes.
>
> COACHING ON THE RUN
> • Run with just your phone: spoken cues for every step, pace checks and kilometre or mile splits, over your
>   music.
> • The current step and time on the lock screen and in the Dynamic Island.
> • Finished runs are saved to Apple Health with their route.
>
> WORKOUTS ON YOUR WATCH
> • Send structured workouts to Apple Watch with one tap.
> • Garmin, COROS, Suunto or Wahoo? Connect your free Intervals.icu account and your workouts reach your watch
>   automatically.
>
> LEARN FROM EVERY RUN
> • Pace, heart rate, power and cadence, with heart-rate zones and splits.
> • Plain-language notes on what each run tells you, and a coach to ask about your training, powered by Apple
>   Intelligence on your device.
>
> PRIVATE BY DESIGN
> • No account, no sign-up, no servers, no ads, no analytics.
> • Your plan and runs stay on your iPhone.
> • Open source: see how every plan is built at github.com/nickcia/trackstar.
>
> TrackStar is a training tool, not medical advice. Check with a doctor before starting a new exercise program.

**Keywords** (100, commas, no spaces after them; words already in the name and subtitle don't need repeating)

`marathon,5k,10k,half,training,plan,pace,garmin,apple watch,couch to 5k,interval,tempo,beginner,runna`

(Check this stays under 100 characters after any edit. Apple may reject a competitor's name in keywords; drop
`runna` if review complains.)

**Support URL:** https://github.com/nickcia/trackstar/issues
**Marketing URL:** https://github.com/nickcia/trackstar
**Copyright:** 2026 Nicholas Cianfaglione

## App Review Information

- Sign-in required: **No**
- Contact: your name, phone and email
- Notes: the "Review notes" in `docs/TESTFLIGHT.md` work here as well.

## App Privacy (App Store Connect › App Privacy)

Answer **"No, we do not collect data from this app."** The label then reads **Data Not Collected**.

Why that's accurate under Apple's definitions ("collect" means sent off the device in a way the developer or
partners can access):
- Plans, runs, Health data and location stay on the device. The Coach uses Apple's on-device model.
- Intervals.icu: workouts go to the user's own Intervals.icu account, only if they choose to connect it. That's
  optional, user-initiated and clearly disclosed in the app, which Apple's guidance lets you leave out.
- Bug reports open a GitHub issue the user writes and sends themselves; nothing is sent automatically.
- If analytics or a server are ever added, this answer has to change first.

Privacy policy URL: https://github.com/nickcia/trackstar/blob/main/PRIVACY.md
