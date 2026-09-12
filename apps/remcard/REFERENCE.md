# REFERENCE — FSRS-5 fidelity audit (G8c)

Core algorithm: the FSRS-5 spaced-repetition scheduler in `lib/tool/fsrs.dart`.
Audited against two upstream, permissively-licensed reference implementations.

## Licenses (both permissive — comparison + attribution allowed)

| Reference | Repo | License | Use here |
|---|---|---|---|
| fsrs4anki | `open-spaced-repetition/fsrs4anki` | MIT (© 2022 open-spaced-repetition) | Formula-level comparison; attributed |
| fsrs-rs | `open-spaced-repetition/fsrs-rs` | BSD-3-Clause (© 2023 Open Spaced Repetition) | Golden numeric oracle; attributed |

No source lines or assets were copied from either repo. Our implementation is
independently written in Dart and only the *formulas and default weights* are
matched. Attribution belongs on the app's About page ("Scheduling by FSRS-5,
open-spaced-repetition, MIT/BSD").

### Version note — the references have moved to FSRS-6

`fsrs4anki_scheduler.js` in the repo today is **FSRS-6 v6.1.1** (21 weights,
`DECAY = -w[20]`), and fsrs-rs's shipping model (`model_v6.rs`) is likewise
21-weight. Our app targets **FSRS-5** (19 weights, fixed `DECAY = -0.5`), which
is the correct model for a phone that stores 19 trained weights. FSRS-5 is
exactly FSRS-6 with `w[19] = 0` and `w[20] = FSRS5_DEFAULT_DECAY = 0.5` — this
is literally how fsrs-rs upgrades a 19-weight parameter set
(`check_and_fill_parameters_fsrs6`: 19 params → extend `[0.0, 0.5]`). With
`w[19] = 0` the short-term `pow(s, -w19)` term is `1` and with `w[20] = 0.5`,
`factor = 0.9^(1/-0.5) - 1 = 19/81`. So every fsrs-rs `*_scalar` function
reduces cleanly to the FSRS-5 formula, and we use those reduced forms as the
oracle for the golden values in `test/fsrs_reference_test.dart`.

## Summary

| | Count |
|---|---|
| Core functions audited | 11 |
| Consistent as-was | 8 |
| Fixed to match reference | 2 (`forgetStability` cap, `shortTermStability` clamp) |
| Intentional deviations (mobile/UI, documented) | 2 (0.1 stability floor; graduated Anki fuzz) |
| Missing → added | 0 |
| **Remaining discrepancies** | **0** ✅ |

## Function-by-function comparison

Reference column cites fsrs-rs `src/model_v6.rs` scalar fns (primary oracle) and
`fsrs4anki_scheduler.js` (secondary). Verdict = 一致 / 有意偏离 / 已修.

| # | Function | Ours (`fsrs.dart`) | Reference | Verdict |
|---|---|---|---|---|
| 1 | 19 default weights `w[0..18]` | `defaultWeights` :41 | Canonical FSRS-5 vector | **一致** — max 15.69105, all match bit-for-bit |
| 2 | `init_stability` | `initialStability` :137 | `init_stability` (fsrs4anki): `max(w[g-1], 0.1)` | **一致** |
| 3 | `init_difficulty` | `initialDifficulty` :140 | `init_difficulty_scalar`: `clamp(w4 - exp(w5·(g-1)) + 1)` | **一致** |
| 4 | `next_difficulty` (+ linear damping + mean reversion) | `nextDifficulty` :143 | `next_difficulty_scalar` / `mean_reversion_scalar` (revert toward `init_difficulty(Easy)`, `w[7]`) | **一致** |
| 5 | `constrain_difficulty` clamp[1,10] | `_clampD` :193 | `D_MIN=1, D_MAX=10` | **一致** |
| 6 | `next_recall_stability` (`w8..10`, hard `w15`, easy `w16`) | `recallStability` :153 | `stability_after_success_scalar` | **一致** — uses old `d`,`s`; golden Case B/E |
| 7 | `next_forget_stability` (`w11..14`) + cap | `forgetStability` :173 | `stability_after_failure_scalar`: cap = `s / exp(w17·w18)` | **已修** — was `min(raw, s)`; now `min(raw, s/exp(w17·w18))`. Case F: s=2,d=5,e=30 → 1.420685 (old gave 2.0) |
| 8 | `next_short_term_stability` (`w17`,`w18`) | `shortTermStability` :187 | `stability_short_term_scalar`: `s·(g≥3 ? max(sinc,1) : sinc)` | **已修** — added `max(sinc,1)` clamp for Good/Easy (no-op at default weights, faithful under custom weights). `pow(s,-w19)` correctly absent (w19=0 in FSRS-5) |
| 9 | `forgetting_curve` (`DECAY=-0.5`, `FACTOR=19/81`) | `retrievability` :81 | `power_forgetting_curve_scalar` | **一致** — R(2,1)=0.946059, R(3,2)=0.929929 |
| 10 | `next_interval` (`requestRetention`, `maximumInterval`, round→clamp) | `intervalFor` :95 | `next_interval_scalar` then `.round().max(1)` | **一致** — at 90%, ivl==round(S); clamp `1..365` |
| 11 | stability lower bound | `next` :219 `max(0.1, s)` | fsrs-rs `S_MIN=0.0001` | **有意偏离** — see below |

### SM-2 bridge (`difficultyFromEase` / `easeFromDifficulty`, `next` reps/lapses)

Not part of upstream FSRS (fsrs-rs `memory_state_from_sm2_fsrs6` solves for both
S and D from an interval; we only migrate difficulty and keep the stored
interval as stability). This is our own compatibility shim for reading cards
written by the app's pre-FSRS SM-2 versions — **有意偏离**, product reason:
on-device upgrade of existing user data, no schema break. Covered by the
existing `SM-2 migration` group in `test/fsrs_test.dart`.

## Intentional deviations (mobile / UI only)

1. **Stability floor `0.1`** (`next` :219, and `initialStability` :137). fsrs-rs
   clamps to `S_MIN = 0.0001`; fsrs4anki floors *initial* stability at `0.1`. We
   apply `0.1` everywhere. Reason: on a phone a sub-0.1-day "interval" is
   meaningless (everything renders as "today/tomorrow"), and `0.1` is exactly
   fsrs4anki's own new-card floor, so no realistic card is affected — recall
   stability only grows, and the post-lapse/short-term paths never dip below
   `0.1` at default weights. Documented, bounded, no user-visible difference.

2. **Graduated fuzz ranges** (`fuzz` :110, `_fuzzRanges` :122): ±15% (2.5–7d),
   ±10% (7–20d), ±5% (20d+). This matches the **Anki backend / py-fsrs**
   canonical fuzz, not fsrs4anki's flat `±5%±1` scheduler fuzz. Reason: it is the
   authoritative graduated fuzz and gives better spread; fuzz is seeded from card
   state (`_fuzzSeed`) so a preview and its review agree. Verdict: matches the
   *reference family*, chosen deliberately over the older JS variant.

## Golden oracle & tests

`test/fsrs_reference_test.dart` (11 cases, all green) encodes numbers produced by
the fsrs-rs `*_scalar` formulas evaluated at our FSRS-5 weights (`w19=0`,
`decay=0.5`), tolerance `1e-4`, intervals exact:

- initial S/D/interval for all four grades;
- six on-schedule Good reviews (S & D chained through the interval it assigns);
- Hard/Good/Easy fan-out from a first Good;
- same-day short-term S for Good/Easy/Hard;
- **post-lapse cap discriminator** (the fixed bug) + a mature-card lapse;
- forgetting-curve values and interval inversion.

The golden values were fixed to the reference first, then `fsrs.dart` was
corrected until the tests passed — never the reverse.

_Audited 2026-09-12 (G8c). `flutter analyze`: 0 issues. `flutter test`: 75/75._
