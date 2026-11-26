# Accord — G6b UI review (2026-11-26)

Based on CI screenshots (UI tour, en / zh-Hant / ja / de, 15 screens each), build 753581e + fixes in 23f2a91.

| Item | Score | Evidence |
|---|---|---|
| Tool on the first screen /15 | 14 | Cold start opens the sample formula on the bench: timeline + lines, 0 taps (F1) |
| Art direction /15 | 12 | Paper grain, amber 52°, Bodoni Moda, bottles filled by top/heart/base on the shelf; Form screens (line editor, material, settings) are still close to stock iOS |
| Type scale /10 | 8 | Bodoni for titles/sections, tabular digits for amounts; CJK falls back to the system serif |
| Colour /10 | 8 | Amber ≤10% of area; three layer colours are the data colours |
| Shape consistency /10 | 8 | Radii 4/12/28 as tokens; system Form rows use their own radius |
| Empty / error / loading /10 | 8 | Empty states with an action; store errors with retry; import errors explain the column |
| Interaction /10 | 8 | Haptics per event, unit cycling on tap, keyboard Done; chart scrub now simultaneous with scrolling |
| Motion discipline /10 | 7 | Few animations (section picker, press scale); no entrance choreography |
| Accessibility /5 | 4 | Labels on chart/stars/rings, adjustable actions; Dynamic Type capped at accessibility2 |
| Icon and logo /5 | 4 | Flacon icon with three layers and Bodoni label |
| **Total** | **81 / 100** | Pass line 75 |

## Veto checks
- V1 first screen is not "nav title + gear + card list": pass (bench is the formula).
- V2 gradient card + corner icon: none.
- V3 banned list: #8 all-caps labels came from system Form section headers → fixed with `.textCase(nil)` (23f2a91). No other hits.
- V6 cold start ≤2 taps: 0 taps.
- V7 Dynamic Type 2×: not overflowing in the tour; buttons now single-line with scale-down (German "Rohstoff hinzufügen").
- V8 contrast: inkSoft #6B6158 on paper #F6F1E7 ≈ 5.6:1.
- V9 signature scene: the evaporation timeline is data-driven (formula → curve) and scrubbable.

## Not done yet
- V5 side-by-side blind comparison with the other 15 apps (needs a separate agent).
- Real-device check (haptics, Face ID, notifications), user acceptance on TestFlight.
- Plural forms ("1 ingredients") are not handled.
