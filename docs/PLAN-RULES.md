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

## 6. Safety validation

`PlanValidator` independently checks every rule above on any plan. The test suite generates over 10,000
plans across goals, levels, schedules, plan lengths, start days, volumes and fitness levels, and
requires every one to pass.

## Coming next

- Adaptation after missed or skipped runs, unusual paces, and changed race dates or availability.
- Matching completed runs to planned workouts.
- Race-time prediction from training.
