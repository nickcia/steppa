# How training plans are built

Plans come from a set of transparent, rules-based steps. There is no AI and no server. The code lives in
`Packages/PlanEngine`. Every tunable number is in [`PlanRules.swift`](../Packages/PlanEngine/Sources/PlanEngine/Plan/PlanRules.swift).
Keep this document in sync with that file.

> This app is not medical advice. These rules follow widely used coaching principles. They are not a
> substitute for a coach or doctor.

## 1. Fitness score and paces

A recent race result gives a **fitness score**: an "effective VO₂max" calculated from two equations
published by Daniels & Gilbert (1979). One gives the oxygen cost of running at a given speed. The other
gives the share of VO₂max you can sustain for a given time. Nothing is copied from proprietary tables.

| Zone | How it's set |
|---|---|
| Easy | 62–70% of the fitness score |
| Marathon | Predicted marathon pace ±2% |
| Threshold | 88% ±2% |
| Interval | 97.5% ±2% |
| Repetition | 105% ±2% |
| Race | Predicted goal-race pace ±1.5% |

- **Old results:** a race more than 180 days old is discounted by 3%.
- **No race result:** fitness is estimated conservatively from experience and weekly volume, and the
  plan says so.
- **Goal times:** paces always come from **current** fitness, never from the goal time. An ambitious
  goal produces a warning, not harder sessions.

## 2. Phases

Weeks run Monday to Sunday. The last week contains the race. The taper is 1 week for 5K and 10K, 2 weeks
for the half marathon and 3 weeks for the marathon. Of the remaining weeks, about 20% are **peak**, 35%
are **build** and the rest are **base**. Plans shorter than the recommended minimum (4, 6, 8 and 12
weeks) get a warning.

## 3. Weekly volume

- Volume starts at your current weekly distance (minimum 8 km).
- Volume peaks at a target set by distance and experience. If you already run more than the target, it
  peaks at your current volume, up to 130% of the target.
- Each loading week grows by at most 10% (8% for beginners), or 1.5 km at very low volume.
- **Step-back week** at 80% after every 3 loading weeks (every 2 for beginners).
- **Taper** relative to the last loading week:

  | Race | Taper weeks |
  |---|---|
  | 5K and 10K | 60% |
  | Half marathon | 75%, then 55% |
  | Marathon | 80%, then 65%, then 45% |

- A partial first week (starting mid-week) gets a proportional share of that week's volume.

## 4. The week

- **Long run** on your chosen day. It takes 30% of the week, rising to 40% with only 2 run days. It is
  capped by distance (12–34 km by goal and level) and by time (1h45 to 3h). It is never longer than the
  rest of the week combined.
- **Quality sessions:**

  | Phase | Beginners | Others |
  |---|---|---|
  | Base | 0 | 1 |
  | Build and peak | 1 | 2 with 4+ run days |
  | Taper | 1 | 1 |

  Step-back weeks drop one session. With only 2 run days there are no sessions.
- **Hard/easy:** quality sessions never fall the day before or after the long-run weekday, or next to
  each other, including across the end of the week.
- **Intensity cap:** at most 20% of weekly distance is at threshold pace or faster.
- **Easy runs** fill the rest of the week. Each is at least 3 km and at most 10, 14 or 18 km by level.
  If your available days can't hold the target volume, the plan stays lighter and says so.
- **Marathon peak (non-beginners):** the long run finishes with up to 40% at marathon pace.
- **Race week:** at most one short session, no later than 4 days before the race. The last 3 days hold
  only short easy runs (6 km, then 4 km the day before).

## 5. Sessions

| Session | Structure |
|---|---|
| Intervals | Warm-up, then 3–8 reps (5K: 800 m; 10K and half: 1 km; marathon: 1.2 km; 400 m in small weeks), each followed by a jog recovery of about ¾ the rep time. Then cool-down. |
| Threshold | Cruise intervals of 1–1.6 km with 60 s jogs. In the peak phase (non-beginners), a continuous tempo run of 3–8 km. |
| Easy / long | A single step with an easy pace range. |

Every workout is a warm-up, repeated blocks and a cool-down. This maps directly onto Apple Watch
structured workouts.

## 6. Matching completed runs

Runs come from Apple Health. Watches from Garmin, Coros and others can write runs there. A run counts
for a planned workout when it meets all of these:

- It is on the same day, or one day either side. Races must be on the day.
- Its distance is 50–160% of the plan. Races must be 90–115%.
- It is at least 1 km.

When several runs could match, the same day wins first, then the closest distance. Each run matches at
most one workout. Matches made or removed by hand are never overridden.

## 7. Adapting the plan

The plan is reconsidered when runs sync, when the race date changes, when available days change, or when
you enter a new race result. Three rules always hold:

- **The past never changes.** Days before today stay as they were. Today and later are re-planned.
- **Missed training is never made up.** Volume restarts from what you actually did and builds by the
  usual safe limits.
- **Within the current week**, the re-plan respects what's already been done. It doesn't add a second
  long run, exceed the week's quality sessions, or put a hard day next to a recent one.

### Missed training

| Situation | Volume resumes at |
|---|---|
| No run for 7–13 days | 80% of the previous loading week |
| No run for 14–27 days | 60% |
| No run for 28–55 days | 40% |
| No run for 56+ days | 25% |
| Less than 85% of planned distance over the last 14 days | That share, but never below 60% (partial training is never treated as worse than a full two-week break) |

Missed-training and pace checks only run when the app has a real record of your running. In the app, that means once you've started ticking runs off (later, once Apple Health is connected). A plan is never cut back just because nothing was logged. The completion check also waits until after the plan's first week. A reduction is applied once. Reviewing
again on the same data doesn't lower volume again.

### Fitness

- **Quality sessions.** If your average pace across at least 3 recent tempo or interval sessions was
  clearly faster than planned (median 3% or more), fitness rises by up to 2%. If clearly slower (5% or
  more), it falls by up to 3%. Increases are smaller than decreases on purpose.
- **Strong efforts.** A run of 3 km or more that implies higher fitness (by over 2%) raises it by up to
  3%. Any run is at most an all-out effort, so it shows at least that much fitness.
- **New race result.** Entering one resets fitness to that result.
- Each piece of evidence is used once. Only runs after the last fitness change count.

### Race date and availability

Changing the race date re-periodises the remaining weeks from where volume currently stands. Changing
run days or the long-run day re-plans from today onto the new days.

## 8. Moving workouts

You can move a workout to another day in the same week. If that day has a workout, the two swap. A move
is refused if it would break a safety rule, for example two hard days in a row, or a hard session in the
last 3 days before the race. Past workouts and the race can't be moved.

Workouts you've moved are kept until the next adaptation, which re-plans the remaining weeks.

## 9. Race-time prediction

Predictions come from the higher of two scores: your fitness score, and your best effort in the last 6
weeks. For long races, low training volume adds a penalty, because equivalence formulas are optimistic
for low-mileage runners:

| Race | Penalty |
|---|---|
| Marathon | Up to +8%, below 60 km/week |
| Half marathon | Up to +4%, below 40 km/week |

The prediction range is ±2%, ±3.5% or ±6%, depending on how confident the fitness score is.

## 10. Safety validation

`PlanValidator` independently checks every rule above on any plan.

**History.** Workouts before the last adaptation were checked when they were planned. They are not
re-judged against changed inputs, such as new run days or a race date that moved closer. Rules that span
the boundary between history and the re-planned days, like no two hard days in a row, are still checked.

**Tests.** The test suite:
- generates over 10,000 plans across goals, levels, schedules, plan lengths, start days, volumes and
  fitness levels;
- adapts thousands of them at different points, with simulated athletes who follow the plan, skip runs,
  take breaks or run faster or slower, and under every kind of change;
- adapts them a second time on top of that.

Every result must pass the validator, leave history untouched and keep workout IDs unique.
