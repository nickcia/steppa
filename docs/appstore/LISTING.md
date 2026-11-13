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
> it has no ads or subscriptions, and your data stays yours.
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
> • Garmin? Connect Garmin Connect in one tap: workouts go to your watch with every step and pace, and your runs
>   come back to TrackStar.
> • COROS, Suunto or Wahoo? Connect your free Intervals.icu account and your workouts reach your watch
>   automatically.
>
> LEARN FROM EVERY RUN
> • Your route on a map, best efforts, pace, heart rate, power, cadence and running form, with heart-rate zones
>   and splits.
> • Fitness, fatigue and form over time, and a gel plan for long runs.
> • Plain-language notes on what each run tells you, and a coach to ask about your training, powered by Apple
>   Intelligence on your device.
>
> PRIVATE BY DESIGN
> • No account, no sign-up, no ads, no analytics.
> • Your plan and runs stay on your iPhone. The one exception is Garmin Connect, which only works through a small
>   server that passes your workouts and Garmin runs between Garmin and your phone.
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

Since Garmin Connect (build 6), TrackStar has a server that stores some data, so the answer is no longer "Data Not
Collected". Answer **"Yes, we collect data from this app"** and declare exactly this:

| Data type | Purpose | Linked to the user? | Used for tracking? |
|---|---|---|---|
| **Health & Fitness › Fitness** | App Functionality | Yes | No |
| **Identifiers › User ID** | App Functionality | Yes | No |

The label then reads **Data Linked to You: Health & Fitness, Identifiers**, and no **Data Used to Track You**.

What each one covers:
- **Fitness:** for athletes who connect Garmin Connect, their planned workouts (sent to Garmin) and the runs Garmin
  sends back (time, distance, heart rate, cadence, power, elevation over the run, device name) pass through and are
  stored on TrackStar's server until the iPhone collects them (at most 30 days). Strictly, heart rate is health
  data, but it's collected here as part of a workout, which Apple counts as Fitness.
- **User ID:** the server keeps the athlete's Garmin user ID (and encrypted Garmin tokens) to talk to Garmin for them,
  linked to a random ID the app makes on first use. It's linked to the user because it identifies their Garmin
  account.

Not declared, and why:
- **Strava sign-in** passes through the server only to add the client secret; nothing is stored. Apple doesn't count
  data that's only processed in real time and not kept.
- **Plans, Health data, routes, location, gear and coach chats** stay on the device (and the user's own iCloud).
  Map images and place names come from Apple Maps; Apple, not the developer, receives those requests.
- **Intervals.icu and Strava** data goes straight between the iPhone and the athlete's own accounts, so the developer
  never receives it.
- **Photos:** add-only, and only the image the athlete chooses to save.
- **Bug and crash reports** are emails the user writes and sends themselves.

If anything else ever goes to the server, or analytics are added, update this table first.

Privacy policy URL: https://github.com/nickcia/trackstar/blob/main/PRIVACY.md
