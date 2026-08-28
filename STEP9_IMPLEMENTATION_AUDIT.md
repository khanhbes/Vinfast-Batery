# Step 9 implementation audit

## Baseline

- Branch: `feature/ai-target-charging-uiux`
- Base SHA: `39409e744b4b8021a47745dd4b9c97c87a27f202`
- Remote baseline: `origin/main` at `4f9d6b982aec9a21ff1ddde2c093372c65a24059`
- Local base was one commit ahead of remote (the completed Step 8 gateway).
- Baseline gateway: 10/10 tests passed.
- Baseline targeted Flutter Smart Charger: 29/29 tests passed.

## Screen inventory

P0 migrated/verified in Step 9:

- App route transition system (`AppMotion`) — reduced-motion support.
- AI Charging Predictor — entry point and guarded navigation.
- Smart Charger card — dedicated setup action and safety-first manual controls.
- Smart Charging Control — new responsive form, preview, confirmation, active,
  restored and history states.
- Settings — secure Smart Charger token configuration.
- Confirmation/stop dialogs — explicit estimated-SOC acknowledgement and OFF
  readback language.

P1 verified through shared theme/components and targeted tests:

- Home, Dashboard, Battery Monitor, Charge Log, Statistics, Maintenance,
  Trip Planner, Notifications and AI Models.
- Shared section header, status chip, error banner, spacing/radius/elevation and
  global page transition tokens are available for incremental migration.

P2 follow-up inventory (no behavior change required for Step 9):

- Login/Register.
- Profile, Vehicle Garage, Vehicle Spec Detail, Guide, Appearance and AI
  Functions settings screens.
- Trip live map.

These P2 screens retain the current design system. Future cleanup should replace
remaining direct `GestureDetector` navigation and ad-hoc 20px cards with the
shared interaction/surface primitives when each screen is next modified.

## Safety decisions

- Gateway owns cutoff scheduling; Flutter countdown is display-only.
- One active session, command lock, idempotency key, relay readback and durable
  SQLite state are enforced.
- Default rollout is shadow mode with automatic cutoff disabled.
- SOC is always labeled estimated (`~`) and never independently triggers OFF.
- Restart never emits ON; relay-off restoration becomes `interrupted`.
- Manual OFF remains available in shadow mode.
- Android release blocks cleartext by default. A scoped legacy exception exists
  only for `167.71.207.121` so the current APK update/API endpoint can work;
  arbitrary LAN gateway cleartext remains debug-only. Remove the exception once
  the public backend has valid HTTPS.

## Known hardware-dependent gate

Live automatic cutoff is implemented but intentionally not enabled. Before
production enablement, configure and validate `SMART_CHARGER_MAX_SESSION_MINUTES`
on the actual charger/vehicle, run shadow sessions, test gateway power loss and
LAN loss, and review charging-curve evidence.

## Final verification

- Gateway: `46 passed` with recovery, idempotency, deadline, relay-readback,
  meter-reset, concurrency and stable-error coverage.
- Flutter Step 9 scope: `74 passed` across models, controller, HTTP service and
  responsive/accessibility widget states.
- Full Flutter suite: `177 passed`.
- Targeted analyzer for all Step 9 Dart files: no issues.
- Android XML and PowerShell syntax gates: passed.
- Final `git fetch --all --prune`: `origin/main` remained at
  `4f9d6b982aec9a21ff1ddde2c093372c65a24059`; no new remote change appeared.
- Debug Android APK: built successfully with emulator gateway URL
  `http://10.0.2.2:8000`.
- APK path: `app/build/app/outputs/flutter-apk/app-debug.apk` (190,925,600 bytes).
- APK SHA-256:
  `0AFA083CAFD348D0F593484CAFC18053C011582A32AB4852E75B18B928A2C865`.
- Android profile build/install/run succeeded on a Pixel 9a emulator (Android
  16/API 36; profile assemble 739.8s). The app reached its authentication screen
  without a runtime error; evidence is stored in `STEP9_PROFILE_QA.png`.
- The emulator had no test account, so no credentials were invented or exposed.
  Authenticated P0 motion/screenshot evidence and live Shelly cutoff remain part
  of the hardware-dependent rollout gate above. The Smart Charging states,
  320dp layout, large text, semantics and reduced-motion behavior are covered by
  targeted controller/widget tests.
