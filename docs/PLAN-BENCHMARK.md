# How Steppa's plans compare with published coaching methods

People reasonably ask whether Steppa's plans are as good as a commercial app's or a coach's. Commercial
plan engines are proprietary, and Steppa collects no outcome data (no servers, no analytics), so we
can't compare race results. What we can do:

1. measure Steppa's generated plans against numbers that well-regarded coaching books and sports-science
   research publish, and say plainly where they differ;
2. ask qualified coaches to review sample plans (see the [coach review kit](#coach-review-kit)).

This page does the first and sets up the second. The rules themselves are in
[PLAN-RULES.md](PLAN-RULES.md).

> We record summary numbers and cite their sources. We never copy a published plan: those are copyrighted.

## Method

The benchmark is a test in the engine's suite:
[`BenchmarkTests.swift`](../Packages/PlanEngine/Tests/PlanEngineTests/BenchmarkTests.swift). Run it with
`cd Packages/PlanEngine && swift test --filter BenchmarkTests`. It prints the full table.

**Plans.** It generates 288 plans: 4 race distances × 3 levels × 4 schedules (3, 4, 5 and 6 run days,
long run on Sunday) × 3 starting volumes (80%, 100% and 125% of a typical starting volume for that race
and level) × 2 lengths (the recommended length and 4 weeks longer). Each plan starts on a Monday, races
on a Sunday and uses a recent race result typical for the level. Every plan must also pass
`PlanValidator`.

**Metrics** (computed from the planned workouts, not the nominal targets):

| Metric | Definition |
|---|---|
| Plan length | The length the app recommends. |
| Peak ÷ start | Highest loading-week target ÷ first week's target. |
| Weekly increase | Largest increase between consecutive loading weeks. Step-back weeks are recovery, not a new baseline. Increases under 1 mile (1.6 km) count as 0%. |
| 2-week increase | Largest increase over two loading weeks. |
| Step-back frequency | One step-back week every N weeks. |
| Long-run share | Long run ÷ the week's planned training distance, over non-taper weeks except race week (mean and maximum). |
| Longest long run | Distance and estimated time. |
| Run vs longest in 30 days | Largest amount by which any run exceeds the longest run in the 30 days before it. Starts from the plan's third week, because the plan doesn't know the runner's earlier runs. The race is excluded. |
| Quality sessions | Most tempo, interval and marathon-pace long runs in any build or peak week, for schedules with 4+ run days. |
| Share below threshold | Distance slower than threshold pace ÷ all training distance. |
| Threshold and interval work | Largest single session's work at that pace ÷ that week's distance, in training weeks. In the taper, volume drops while intensity is kept on purpose, so this share rises. The validator's 20% weekly cap still applies there. |
| Taper length and cut | Number of taper weeks. Cut = 1 − (mean taper-week distance ÷ mean of the last 3 loading weeks). |
| Pace relationships | Checked separately for fitness scores from 30 to 70 (about a 34-minute to a 16-minute 5K). |

**Rules for the ranges.**
- A range changes only when the cited source supports the change. It is never widened to make a plan
  pass, and the validator is never loosened.
- When a metric is outside its range and the engine isn't changed, it's listed as a **known deviation**,
  with the reason in the test and below. If the engine later moves back into range, the test fails until
  the entry is removed, so the list can't go stale.
- Some ranges are **rules stated by an author** (for example Daniels' "long run ≤ 25% of the week").
  Others are **read from published schedules** (for example "longest run in novice marathon plans").
  The second kind is approximate. Plans vary, and we report them as ranges.

## Results

✅ inside the range. ⚠️ outside: a known deviation, explained below. Steppa's figures are the minimum to
maximum across the grid. B / I / A = beginner / intermediate / advanced.

### Volume and progression

| Metric | Reference | Source | Steppa | |
|---|---|---|---|---|
| Recommended plan length | 5K 6–12 wk · 10K 8–12 · half 10–16 · marathon 12–24 | Higdon; Pfitzinger & Latter; Pfitzinger & Douglas; Daniels (schedules) | 8 · 10 · 12 · 16 | ✅ |
| Peak ÷ starting volume | 1.0–2.7× | Higdon; Pfitzinger & Douglas (schedules) | 1.1–2.2× | ✅ |
| Largest weekly increase | ≤ 10% | Pfitzinger & Douglas; the "10% rule" tested by Buist 2008 | 8% (B), 10% (I/A) | ✅ |
| Largest 2-week increase | ≤ 30% | Nielsen 2014 | 12–25% | ✅ |
| Step-back week | every 3–4 weeks | Higdon (every 3rd week); Daniels (hold load 3–4 weeks) | every 3rd (B), 4th (I/A) | ✅ |
| Any run vs longest in prior 30 days | ≤ +10% | Frandsen 2025 | ≤ +10% | ✅ |

### Long runs

| Metric | Reference | Source | Steppa | |
|---|---|---|---|---|
| Long-run share, mean | 25–50% | Daniels (≤ 25%, ≤ 30% under 64 km/wk); Higdon novice plans reach ~50% | 29–48% | ✅ |
| Long-run share, max | ≤ 50% | Higdon | 30–50% | ✅ |
| Longest long run, time | ≤ 150 min (≤ 180 marathon) | Daniels (150 min); Higdon, Pfitzinger & Douglas for the marathon | ≤ 130 min; marathon ≤ 180 | ✅ |
| Longest long run, half | B 14–19 km · I 16–22 · A 19–26 | Higdon; Pfitzinger & Latter (schedules) | B 8.5–14 · I 20–21 · A 24 | ⚠️ B · ✅ I, A |
| Longest long run, marathon | B 26–32 km · I 29–35 · A 32–35 | Hansons (26 km); Higdon (32 km); Pfitzinger & Douglas (32–35 km) | B 15.4–21.5 · I 22.5–29 · A 26.5–34 | ⚠️ all (closer; see below) |
| Longest long run, 5K / 10K | no citable range | — | 5K: 4–7.4 · 9.4–16 · 15–18; 10K: 5.2–12 · 12.2–18 · 20 | info |

### Intensity

| Metric | Reference | Source | Steppa | |
|---|---|---|---|---|
| Share below threshold | ≥ 75% (about 80/20) | Seiler 2010; Stöggl & Sperlich 2015 | 88–100% | ✅ |
| Quality sessions per week (build/peak) | B 0–1 · I 1–2 · A 2 | Higdon (novice plans: none); Daniels "2Q" | B 0–1 · I 2 · A 2 | ✅ |
| Threshold work per session | ≤ 10% of the week | Daniels | ≤ 10% | ✅ |
| Interval work per session | ≤ 8% of the week | Daniels | ≤ 8% | ✅ |

### Taper

| Metric | Reference | Source | Steppa | |
|---|---|---|---|---|
| Taper length | 5K/10K 1–2 wk · half 1–3 · marathon 2–3 | Mujika & Padilla 2003 (4–28 days); Bosquet 2007 (~2 wk); Pfitzinger & Douglas and Smyth & Lawlor 2021 (3 wk marathon) | 1 · 2 · 3 | ✅ |
| Taper volume cut, half | 41–60% | Bosquet 2007 | 43–53% | ✅ |
| Taper volume cut, marathon | 41–60% | Bosquet 2007 | 41–48% (one beginner case just under 41%) | ✅ I/A · ⚠️ B |
| Taper volume cut, 5K / 10K | 41–60% | Bosquet 2007 | 43–73% | ⚠️ |

### Paces

Checked for every fitness score from 30 to 70 in steps of 2.5.

| Relationship | Reference | Source | Steppa | |
|---|---|---|---|---|
| Threshold pace | between 10K and half-marathon race pace | Daniels (about 1-hour race pace); Pfitzinger (15K to half-marathon pace) | inside | ✅ |
| Interval pace | race pace for a 10–15 min effort; 3K–5K pace for runners who race 3K in ≤ ~15 min | Daniels; Pfitzinger | ≈ 15-min race pace | ✅ |
| Easy pace | midpoint 10–35% slower than marathon pace | Pfitzinger & Douglas (general aerobic 15–25% slower; recovery slower still) | 17–21% slower | ✅ |
| Order | threshold faster than marathon pace, marathon pace faster than easy | all | holds | ✅ |

Pfitzinger's 3K–5K guide is only checked above a score of 35. A slower runner takes longer than
15 minutes to race 3K, so 3K pace is slower than Daniels' interval pace for them.

## Engine changes made because of this benchmark

Each change is conservative: it lowers load or spreads it more evenly, it has a source, and the safety
sweeps still pass. `PlanBuilder.engineVersion` went from 1 to 2 (and to 3 in the second round below). [PLAN-RULES.md](PLAN-RULES.md) is updated.

| # | Finding | Before | Change | After |
|---|---|---|---|---|
| 1 | Two-week growth for low-volume beginners exceeded Nielsen's 30% | up to 38% (8 → 9.5 → 11 km) | Low-volume minimum step 1.5 km → 1 km | ≤ 25% |
| 2 | Half and marathon tapers were gentler than Bosquet's 41–60% | half 34–46%, marathon 29–43% | Half 75/55% → 70/45%; marathon 80/65/45% → 75/60/40% | half 43–53%, marathon 41–48% |
| 3 | When the run days couldn't hold the target, step-back and taper weeks barely cut (they cut from a target never reached) | marathon taper cut as low as 23% | Step-back and taper weeks cut from what the last loading week actually held | as row 2 |
| 4 | Advanced runners with Mon–Thu + weekend got 1 session, not 2 | greedy choice: Wednesday blocked Tue + Thu | Session days chosen to fit the most sessions first | 2 sessions |
| 5 | Sessions sized against the target week overshot Daniels' caps when the week couldn't hold its target | threshold up to 10.7%, intervals up to 10.2% | Sessions sized against what the week actually holds | ≤ 10% / ≤ 8% |
| 6 | Single runs jumped when the week's structure changed (a session added, a step-back ended) | up to +38% over the longest run in the last month | No easy or long run longer than 110% of the longest run in the previous 24 days | ≤ +10% |

**Second round (engine version 3): long runs, strides and hills.** The maintainer chose to close the
long-run gap using options (a) and (b) from the first round:

| # | Change | Before | After |
|---|---|---|---|
| 7 | Long-run share for the half 38% (up to 45%) and marathon 42% (up to 50%), still capped at half the week and by the 10% rule | 30–40% | half 38–50%, marathon 41–50% |
| 8 | Marathon peaks 60 / 75 / 100 km (were 45 / 65 / 95); half beginner 40 km (was 35) | — | marathon long runs B up to 21.5 km, I up to 29, A up to 34 |
| 9 | Time caps: half 2h (beginner) or 2h15; marathon 3h for every level | marathon beginner 2h45 | — |
| 10 | A plan starting mid-week shrank its long run to the size of its one easy run, and the 10% rule then held later weeks to that size | first long runs 3.5 km on a 30 km/week runner | short weeks move distance to the easy runs; the 10% rule assumes a usual long run of 30% of the reported weekly distance until the plan has its own history |
| 11 | Strides (4–6 × 20 s) on 1–2 easy runs a week; hill repeats alternate with threshold in base weeks from week 6 | none | — |

One benchmark definition was also aligned with its source. Daniels' 2Q plans count a long run with
marathon-pace segments as a quality session, so the benchmark does too.

Side effects: some weeks now plan slightly less than their target, and show "volume limited by
availability". The shortest intermediate half-marathon long run in the grid fell from 16 km to 15.1 km
because of change 6.

## Known deviations

These are outside a published range and deliberately left as they are, for now.

**1. Some half and marathon long runs are still shorter than published plans,** after the second-round
changes above. What remains is deliberate:
- **Beginner marathon (15–22 km vs 26–32):** the 3-hour cap on time on feet binds first. At beginner easy
  paces, 3 hours is about 21–24 km. Published novice plans go further and take longer.
- **Beginner half (8.5–14 km vs 14–19):** beginners grow 8% a week with an easier week every third week,
  and no run may exceed the last few weeks' longest by more than 10%. From a low start in a 12-week plan
  the long run reaches about 14 km. Longer plans get closer.
- **Intermediate and advanced marathon:** typical inputs reach the range (up to 29 and 34 km). Short
  plans and low starting mileage are held back by the 10% rule.

**2. 5K and 10K race-week cuts are sometimes deeper than Bosquet's 60%** (up to 73%). The single taper
week is race week, whose last three days are short easy runs by design. That is still within Mujika &
Padilla's 60–90%. We haven't changed it, because adding race-week running isn't clearly safer.

**3. One beginner marathon case cuts 40.7%, just under 41%.** Beginners step back every third week, so
the average of the last three loading weeks includes lower weeks.

## Where Steppa differs from a coach-built plan

The benchmark checks numbers, but a coach also brings things the numbers don't capture:

- **Strides and hills are basic.** Strides are on 1–2 easy runs a week and hill repeats alternate with
  threshold in the later base weeks, but there's no repetition-pace session or hill sprints.
- **No cross-training, strength or mobility work**, and no run-walk option. The shortest run is 3 km, so
  a true beginner who can't yet run continuously isn't served (Higdon's novice 5K and Galloway's method
  are for them).
- **No medium-long runs, marathon-pace runs outside the long run, or tune-up races.** All are common in
  Pfitzinger's plans.
- **Early plateau.** Volume can reach its peak target by mid-plan and hold flat (sample B holds ~65 km
  from week 6 to week 13). Published plans usually keep building until 3–5 weeks out.
- **Week shape is formulaic.** Easy runs can equal the long run in length, and the day after the long
  run can be an easy run as long as the long run (sample D). A coach would shorten it or make it a rest
  day.
- **No individual judgement.** No account of injury history, age, sex, menstrual cycle, sleep, work or
  life stress, heat, altitude or terrain. Steppa adapts to completed runs, missed runs and faster or
  slower sessions, but a coach can read context.
- **Fitness comes from equations.** The Daniels & Gilbert equations and the low-mileage penalty for long
  races are population-level estimates.
- **Not tested on outcomes.** We don't know how many Steppa users finish, improve or get injured. This
  benchmark checks plans against methods, not results.

## Coach review kit

If you're a certified running coach (for example UESCA, RRCA, USATF, England Athletics or World
Athletics), we'd be grateful for a review. Please look at the plans below, fill in the questionnaire
and open an issue on the repository (or email the maintainer). Your answers may be quoted in this
document; tell us if you'd like credit or anonymity.

The plans are rendered from the engine by `CoachReviewSamples` in
[`BenchmarkTests.swift`](../Packages/PlanEngine/Tests/PlanEngineTests/BenchmarkTests.swift).
Regenerate them with `STEPPA_PRINT_SAMPLES=1 swift test --filter CoachReviewSamples`.

**Key:** E = easy run, L = long run, T = threshold (cruise intervals with 60 s jogs, or "cont." for a
continuous tempo), I = intervals with jog recoveries of about ¾ the rep time. Session distances in
brackets include a 1.5–2 km warm-up and 1–1.5 km cool-down. "@M" is marathon pace. Distances in km.
Blank days are rest days.

#### A. Half marathon, beginner: 12 weeks, 3 run days, 18 km/week now, 5K in 32:00

Paces (min/km): easy 7:57–8:43, marathon 7:09, threshold 6:40, interval 6:09. Predicted race time: 2:27.

| Wk | Phase | Mon | Tue | Wed | Thu | Fri | Sat | Sun | km |
|---|---|---|---|---|---|---|---|---|---|
| 1 | base |  | E 5.5 |  | E 5.5 |  |  | L 6 | 17 |
| 2 | base |  | E 6 |  | E 6 |  |  | L 6.6 | 18.6 |
| 3 | base (step-back) |  | E 4.5 |  | E 4.5 |  |  | L 5 | 14 |
| 4 | base |  | E 6.5 |  | E 6.5 |  |  | L 7.2 | 20.2 |
| 5 | build |  | E 7.9 |  | I 4×400 m (4.9) |  |  | L 7.9 | 20.7 |
| 6 | build (step-back) |  | E 5 |  | E 5 |  |  | L 5.5 | 15.5 |
| 7 | build |  | E 8.6 |  | I 4×400 m (4.9) |  |  | L 8.6 | 22.1 |
| 8 | build |  | E 9.4 |  | T 2×1000 m (4.7) |  |  | L 9.4 | 23.5 |
| 9 | peak (step-back) |  | E 6 |  | E 6 |  |  | L 6.5 | 18.5 |
| 10 | peak |  | E 10 |  | T 2×1000 m (4.7) |  |  | L 10.3 | 25 |
| 11 | taper |  | E 5.5 |  | E 5.5 |  |  | L 6 | 17 |
| 12 | taper |  | E 3.5 |  | E 3.5 |  |  | **RACE** | 7 |

#### B. Marathon, intermediate: 16 weeks, 5 run days, 45 km/week now, 10K in 48:00

Paces (min/km): easy 5:53–6:29, marathon 5:14, threshold 4:54, interval 4:31. Predicted race time: 3:40.

| Wk | Phase | Mon | Tue | Wed | Thu | Fri | Sat | Sun | km |
|---|---|---|---|---|---|---|---|---|---|
| 1 | base |  | E 8 | T 2×1600 m (7) | E 8 |  | E 8 | L 13.5 | 44.5 |
| 2 | base |  | E 8.5 | T 3×1600 m (8.8) | E 8.5 |  | E 8.5 | L 14.8 | 49.1 |
| 3 | base |  | E 9.5 | T 3×1600 m (8.8) | E 9.5 |  | E 9.5 | L 16.2 | 53.5 |
| 4 | base (step-back) |  | E 7 | E 7 | E 7 |  | E 7 | L 12.5 | 40.5 |
| 5 | base |  | E 11 | T 3×1600 m (8.8) | E 11 |  | E 11 | L 17.8 | 59.6 |
| 6 | build |  | T 4×1600 m (10.5) | E 12 | I 4×1200 m (10.8) |  | E 12 | L 19.5 | 64.8 |
| 7 | build |  | T 4×1600 m (10.5) | E 12 | I 4×1200 m (10.8) |  | E 12 | L 19.5 | 64.8 |
| 8 | build (step-back) |  | E 9 | T 3×1600 m (8.8) | E 9 |  | E 9 | L 15.5 | 51.3 |
| 9 | build |  | T 4×1600 m (10.5) | E 12 | I 4×1200 m (10.8) |  | E 12 | L 19.5 | 64.8 |
| 10 | build |  | T 4×1600 m (10.5) | E 12 | I 4×1200 m (10.8) |  | E 12 | L 19.5 | 64.8 |
| 11 | peak |  | E 12 | T 6 cont. (9.5) | E 12 |  | E 12 | L 19.5 (last 8 @M) | 65 |
| 12 | peak (step-back) |  | E 9 | T 5 cont. (8.5) | E 9 |  | E 9 | L 15.5 | 51 |
| 13 | peak |  | E 12 | T 6 cont. (9.5) | E 12 |  | E 12 | L 19.5 (last 8 @M) | 65 |
| 14 | taper |  | E 9 | T 2×1600 m (7) | E 9 |  | E 9 | L 14.5 | 48.5 |
| 15 | taper |  | E 6.5 | T 2×1600 m (7) | E 6.5 |  | E 6.5 | L 11.5 | 38 |
| 16 | taper |  | E 5 | E 5 | E 5 |  | E 4 | **RACE** | 19 |

#### C. 5K, advanced: 8 weeks, 6 run days, 50 km/week now, 5K in 19:30

Paces (min/km): easy 5:01–5:31, marathon 4:25, threshold 4:10, interval 3:50. Predicted race time: 19:30.

| Wk | Phase | Mon | Tue | Wed | Thu | Fri | Sat | Sun | km |
|---|---|---|---|---|---|---|---|---|---|
| 1 | base | E 6.5 | T 3×1600 m (8.8) | E 6.5 | E 6.5 | E 6.5 | L 15 |  | 49.8 |
| 2 | base | E 7 | T 3×1600 m (8.8) | E 7 | E 7 | E 7 | L 16.5 |  | 53.3 |
| 3 | base | E 8 | T 3×1600 m (8.8) | E 8 | E 8 | E 8 | L 18 |  | 58.8 |
| 4 | base (step-back) | E 6.5 | E 6.5 | E 6.5 | E 6.5 | E 6.5 | L 14 |  | 46.5 |
| 5 | build | I 5×800 m (9.5) | E 7.5 | T 3×1600 m (8.8) | E 7.5 | E 7.5 | L 18 |  | 58.9 |
| 6 | build | I 5×800 m (9.5) | E 7.5 | T 3×1600 m (8.8) | E 7.5 | E 7.5 | L 18 |  | 58.9 |
| 7 | peak | I 5×800 m (9.5) | E 7.5 | T 5.5 cont. (9) | E 7.5 | E 7.5 | L 18 |  | 59 |
| 8 | taper | E 5.5 | I 5×400 m (6.6) | E 5.5 | E 5.5 | E 4 | **RACE** |  | 27.1 |

#### D. 10K, intermediate: 10 weeks, 4 run days, 25 km/week now, no race result

Paces (min/km): easy 6:18–6:56, marathon 5:37, threshold 5:15, interval 4:50. Predicted race time: 51:40.
With no race result, fitness is estimated conservatively from experience and volume.

| Wk | Phase | Mon | Tue | Wed | Thu | Fri | Sat | Sun | km |
|---|---|---|---|---|---|---|---|---|---|
| 1 | base | E 5.5 |  | T 2×1000 m (5.8) |  | E 5.5 |  | L 7.5 | 24.3 |
| 2 | base | E 6.5 |  | T 2×1000 m (5.8) |  | E 6.5 |  | L 8.2 | 27 |
| 3 | base | E 7.5 |  | T 2×1000 m (5.8) |  | E 7.5 |  | L 9 | 29.8 |
| 4 | base (step-back) | E 5.5 |  | E 5.5 |  | E 5.5 |  | L 7 | 23.5 |
| 5 | build | E 9 |  | I 6×400 m (7.2) |  | T 2×1600 m (7) |  | L 9.9 | 33.1 |
| 6 | build | E 10.8 |  | I 7×400 m (7.8) |  | T 2×1600 m (7) |  | L 10.8 | 36.4 |
| 7 | build | E 11.8 |  | I 3×1000 m (8.1) |  | T 2×1600 m (7) |  | L 11.8 | 38.7 |
| 8 | peak (step-back) | E 7 |  | I 6×400 m (7.2) |  | E 7 |  | L 9 | 30.2 |
| 9 | peak | E 12.9 |  | I 3×1000 m (8.1) |  | T 4 cont. (7.5) |  | L 12.9 | 41.4 |
| 10 | taper | E 6.5 |  | I 3×400 m (5.3) |  | E 6 |  | **RACE** | 17.8 |

### Questionnaire

About you
1. Certification(s), years coaching, and the athletes you mostly coach (level, distances).
2. Would you like to be credited by name, or stay anonymous?

For each sample plan (A–D)
3. Would you give this plan, unchanged, to the runner described? (yes / with changes / no)
4. Rate 1 (poor) to 5 (excellent), with a sentence on any score of 3 or below:
   - weekly volume and its progression;
   - long-run length and progression;
   - choice, size and placement of quality sessions;
   - easy/hard balance across the week;
   - taper and race week;
   - paces for the stated race result.
5. Is anything in it **unsafe** for this runner? What, and why?
6. The three changes you'd make first.

Overall
7. Which known deviation or gap above matters most? For the long-run gap, which option would you choose:
   more weekly volume, a larger long-run share, or keeping it conservative with a warning?
8. Is there any rule in [PLAN-RULES.md](PLAN-RULES.md) you disagree with?
9. For which runners would you advise against using a rules-based plan like this at all?

## References

Coaching books and plans
- Daniels, J. *Daniels' Running Formula*, 3rd ed. Human Kinetics, 2014 (4th ed. 2021). Training-pace
  definitions, long-run limit (lesser of 25% of weekly mileage or 150 min), per-session caps for
  threshold (10%) and interval (8%) work, "2Q" plans.
- Daniels, J., Gilbert, J. *Oxygen Power: Performance Tables for Distance Runners*. 1979.
- Pfitzinger, P., Douglas, S. *Advanced Marathoning*, 3rd ed. Human Kinetics, 2019. 12- and 18-week
  marathon schedules, 3-week taper, pace guidance.
- Pfitzinger, P., Latter, P. *Faster Road Racing: 5K to Half Marathon*. Human Kinetics, 2015.
- Higdon, H. Free training programs (Novice and Intermediate 5K, 10K, half marathon and marathon).
  halhigdon.com, accessed November 2026. Step-back every third week; the novice marathon's longest run
  is 20 miles.
- Humphrey, L., with Hanson, K. and Hanson, K. *Hansons Marathon Method*, 2nd ed. VeloPress, 2016.
  Longest run 16 miles.

Research
- Seiler, S. (2010). What is best practice for training intensity and duration distribution in endurance
  athletes? *Int J Sports Physiol Perform* 5(3):276–291. doi:10.1123/ijspp.5.3.276
- Stöggl, T. L., Sperlich, B. (2015). The training intensity distribution among well-trained and elite
  endurance athletes. *Front Physiol* 6:295. doi:10.3389/fphys.2015.00295
- Mujika, I., Padilla, S. (2003). Scientific bases for precompetition tapering strategies. *Med Sci
  Sports Exerc* 35(7):1182–1187. PMID 12840640. (Taper 4–28 days; keep intensity, cut volume 60–90%,
  cut frequency by no more than 20%.)
- Bosquet, L., Montpetit, J., Arvisais, D., Mujika, I. (2007). Effects of tapering on performance: a
  meta-analysis. *Med Sci Sports Exerc* 39(8):1358–1365. PMID 17762369. (About 2 weeks, volume cut
  41–60%, intensity and frequency kept.)
- Smyth, B., Lawlor, A. (2021). Longer disciplined tapers improve marathon performance for recreational
  runners. *Front Sports Act Living* 3:735220. doi:10.3389/fspor.2021.735220
- Nielsen, R. Ø., et al. (2014). Excessive progression in weekly running distance and risk of
  running-related injuries: an association which varies according to type of injury. *J Orthop Sports
  Phys Ther* 44(10):739–747. (More than 30% over 2 weeks was linked to distance-related injuries in
  novices.)
- Buist, I., et al. (2008). No effect of a graded training program on the number of running-related
  injuries in novice runners. *Am J Sports Med* 36(1):33–39. (The "10% rule" didn't reduce injuries vs.
  a standard program. We use 10% as a common coaching convention, not as proven protection.)
- Frandsen, J. S. B., et al. (2025). How much running is too much? Identifying high-risk running
  sessions in a 5200-person cohort study. *Br J Sports Med* 59(17):1203–1210. (Overuse injuries rose
  when a single run exceeded the longest run of the previous 30 days by more than 10%. Week-to-week
  ratios weren't associated with injury.)
