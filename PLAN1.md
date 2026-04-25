# UI/UX Sync Plan For Flutter Mobile

## Summary
Create `UIUX_SYNC_PLAN.md` at the repo root. The document will instruct an AI agent to recreate the source app’s mobile UI/UX in a Flutter app, focusing only on the real phone experience inside the mockup, not the React desktop demo shell.

Target style: VinFast Feliz Neo companion app with Material 3 dark theme, soft rounded surfaces, bottom navigation, animated tab transitions, bilingual English-first UI copy, and placeholder vehicle imagery allowed for prototype parity.

## Key UI/UX Requirements
- Build 5 main tabs: `Home`, `Trip`, `Health`, `Service`, `Settings`.
- Use a mobile-first Flutter layout with:
  - dark scaffold background `#1a1c1e`
  - Material 3 tonal cards and buttons
  - rounded cards around `24px`
  - FAB-style square buttons around `16px` radius
  - bottom navigation bar with animated active pill
  - subtle motion on page changes, progress bars, add form expansion, and button press states
- Preserve the source app’s core visual identity:
  - calm EV dashboard feel
  - Roboto-like typography
  - pale blue primary color `#d1e4ff`
  - blue primary container `#00497d`
  - muted surface variant `#43474e`
  - success `#4ade80`, warning `#fbbf24`, error `#ffb4ab`
- Keep UI copy bilingual but English-led, for example:
  - `Dashboard / Bảng điều khiển`
  - `Trip Planner / Lộ trình`
  - `Battery Health / Pin`
  - `Service / Bảo dưỡng`
  - `Settings / Cài đặt`
- Use placeholder vehicle image initially, matching the current prototype behavior. The plan should note that production can later replace it with a real VinFast Feliz Neo asset.

## Flutter Implementation Guidance
- Create shared theme tokens for colors, text styles, spacing, radii, shadows, and motion durations.
- Add app-level data models equivalent to:
  - `BatteryState`: percentage, SOH, estimated range, temperature
  - `UserProfile`: name, weight, vehicle model, total ODO
  - `MaintenanceItem`: name, current km, limit km, status, icon
  - `TripPrediction`: consumption percentage and reasoning
- Implement screens as separate widgets:
  - `HomeScreen`: vehicle hero image, active chip, charge/range/ODO metrics, battery health tile
  - `TripPlannerScreen`: destination input, AI/prediction loading state, route result card, recent trips
  - `BatteryHealthScreen`: circular SOH indicator, efficiency history chart, driving achievement panel
  - `MaintenanceScreen`: add-item expandable form, active maintenance logs, progress bars, software update card
  - `SettingsScreen`: grouped list sections, toggle row, action chips, sign-out button
- If no AI backend exists yet, Trip Planner should use the same fallback UX: generate/show a plausible consumption result and reasoning while keeping the UI ready for real service integration.

## Test Plan
- Verify all 5 tabs render on common mobile sizes without clipping or overlapping.
- Verify bottom navigation changes active tab with visible animated indicator.
- Verify Service add form opens/closes, validates empty fields, and adds a maintenance row.
- Verify Trip Planner shows loading state, then prediction result.
- Verify chart/progress/circular indicators are visible in dark theme.
- Verify bilingual labels fit within buttons, cards, list rows, and nav items.

## Assumptions
- The target app is Flutter mobile.
- Scope is the mobile UI only; React desktop side panels and phone-frame showcase are excluded.
- `UIUX_SYNC_PLAN.md` should be created at the repo root.
- Placeholder vehicle image is acceptable for the prototype.
- The agent receiving the file should preserve the current UX structure before adding new product features.
