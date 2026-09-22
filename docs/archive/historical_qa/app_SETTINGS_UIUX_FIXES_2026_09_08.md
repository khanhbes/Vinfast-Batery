# Settings UI/UX fixes — 2026-09-08

## Implemented

- Settings groups and Smart Charger / AI Studio tabs use a restrained fade/slide entrance (380 ms), without blocking interaction. System reduced-motion disables this entrance.
- Smart Charger: scrollable tabs with scaled height; bounded app-bar titles; wrapping protection values and section headings; wrapping label/value rows; native action buttons with 48 dp minimum height and disabled/pressed feedback; switches disabled during busy operations.
- AI Studio: scaled toolbar/tabs, shorter tab labels, responsive equal-height dataset statistics, wrapping section headings and slider labels, naturally growing training button, independent tab scroll keys.
- Empty server datasets now display as empty rather than falling back to demonstration records.
- AI server availability no longer implies Shelly connectivity or a fabricated 740 W measurement.
- Relay-test dialog explicitly says hardware testing is unavailable; no false success/safety confirmation. No relay commands were added or sent.

## Verification and remaining scope

- `settings_studio_layout_test.dart`: 5 tests passed. Covers empty and populated datasets with long identifiers and multiple badges, switching tabs, scrolling and displaying mocked training results at 320 dp with 100%/200% text, plus reduced motion.
- `responsive_cards_test.dart`: 17 tests passed during this change.
- These are targeted tests, not certification of every settings function.
- Still requires device QA for Smart Charger LAN/cloud configuration, keyboard/dialog layouts, large populated datasets, training result cards, real authentication and hardware workflows. No real training, Firebase writes, relay operations, APK build or deployment performed.
- Existing worktree edits from earlier UI fixes were preserved.

## Follow-up pass

- Dataset record headers and metric rows wrap; energy displayed in Wh.
- Evaluation header wraps; MAPE/MAE/R² cards use responsive equal-height rows. Removed unconditional claim that evaluation means deployment.
- LAN/Cloud cards switch between one and two columns and have matching row heights. Headers wrap; buttons use minimum 48 dp targets and block duplicate checks while busy.
- LAN/Cloud badges use saved verification state, not hardcoded online claims. Host/IP show configuration rather than example addresses. Verification is historical, not a live connectivity guarantee.
- Static analysis of the changed screens and tests passed before the final copy-only verification-label adjustment; final validation is recorded in the handoff.
