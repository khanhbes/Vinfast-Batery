# v1.1.5 QA gate evidence

Date: 2026-09-20 (Asia/Ho_Chi_Minh)
Source SHA requested: `41b5922a` (`feature/ios-platform`)

## Executed gates

| Gate | Result | Evidence |
|---|---|---|
| `flutter pub get` | PASS | Dependencies resolved successfully with Flutter 3.41.1 SDK cache. |
| `flutter analyze --no-pub` | BLOCKED | Process displayed `Analyzing app...` but produced no result and was stopped after a bounded timeout. No pass is inferred. |
| Backend `python -m pytest -q web/tests` | PASS | `189 passed, 1 warning in 30.63s`; warning was pytest cache permission only. |
| Smart Charger Gateway `python -m pytest -q` | PASS | `56 passed in 41.44s`. |
| Firestore Rules `npm.cmd test` | BLOCKED | Rules test requires a running Firestore emulator; direct run failed with “host and port ... must be specified”. Firebase emulator execution was not available in this environment. |
| Cloud Run staging | BLOCKED | Google Cloud SDK 585.0.0 is now installed, but interactive `gcloud auth login` requires browser verification and no credentials/project/IAM were available to this run. No deployment was claimed. |
| v1.1.5 APK build/install | NOT RUN | Build requires a verified HTTPS staging URL. Existing APK is `1.1.4+114` and is explicitly excluded from new evidence. |

An additional bounded compile attempt used `--dart-define=APP_API_BASE_URL=https://staging.invalid` only to detect build health. Gradle stayed at `assembleRelease` without completion for approximately two minutes and was stopped; no artifact was accepted and the existing APK timestamp/hash remained unchanged.

## Temporary local API check (2026-09-21)

The Flask API was started directly from `web` with the ignored `.env.laptop` configuration. `GET http://127.0.0.1:5000/api/health` returned HTTP 200 with a request ID. `GET http://127.0.0.1:5000/api/ready` returned HTTP 200; Firebase and AI were reported ready. The process was stopped after the check.

Cloudflare Quick Tunnel installation succeeded, but creating an unauthenticated public tunnel was not executed by the agent because it would expose the local Firebase-backed API. A user-run, explicitly approved tunnel or an authenticated named tunnel is required before using this URL in an APK. This local check is not staging or production evidence.

## Safe local-debug fallback (2026-09-21)

`AppConstants` now permits `http://10.0.2.2:5000`, `localhost`, or `127.0.0.1` only in non-release builds. Release builds still reject every non-HTTPS endpoint. The targeted unit test passed `3/3`. A debug APK was built successfully (not release evidence): package `com.bes.vinbatery`, version `1.1.5`, code `115`, SHA-256 `B6BDE2D366A905A4AB618AA52FBFC4D609220EDA4C6B1116BD09D930B197E948`. Emulator startup then failed to register an ADB device after a local AVD launch, so APK installation/runtime was not claimed.

The release compile was subsequently successful with `APP_API_BASE_URL=https://staging.invalid` only as a compile check (`assembleRelease` 255.6s). Badging was `com.bes.vinbatery`, `1.1.5`, code `115`; APK SHA-256 was `0B7C10A5D978FA60A998FA5775EF1187F9C2F43B386C5EC7B73A82DB5541DFAE`; `apksigner` v2 verification passed. This APK is not QA evidence because the endpoint is intentionally invalid and it was not installed.

`flutter analyze --no-pub` was retried after the fixes, remained at `Analyzing app...` for a bounded timeout, and was stopped. Compile success does not count as analyzer pass.

The Pixel 9a AVD could not register with ADB. Verbose emulator output repeatedly reported access denied creating `C:\Users\khanh\.android\emu-last-feature-flags.protobuf.lock`; retrying with a workspace metadata directory did not produce an ADB device. Emulator installation, screenshots and runtime interaction remain blocked.

## Safety

No production account, vehicle, Shelly relay, Firebase Admin key, token, or secret value was written to this evidence. No source file was changed during the gate run.

## Quick Tunnel staging update (2026-09-21)

The user started an explicitly approved Cloudflare Quick Tunnel to the local API. The tunnel hostname was `poultry-crown-sunrise-behalf.trycloudflare.com`; it is temporary QA infrastructure only and is not a production endpoint.

External read-only smoke checks passed:

- `GET https://poultry-crown-sunrise-behalf.trycloudflare.com/api/health` -> HTTP 200, `success=true`, request ID present.
- `GET https://poultry-crown-sunrise-behalf.trycloudflare.com/api/ready` -> HTTP 200, Firebase `ready`, AI `ready`, request ID present.

Using that HTTPS hostname, a new release APK was built from source SHA `41b5922aef1fe5d4b13db2d765cc0c4ce5c39dc7` plus the uncommitted working-tree fixes:

- package: `com.bes.vinbatery`
- version: `1.1.5` / code `115`
- artifact: `app/build/app/outputs/flutter-apk/app-release.apk`
- SHA-256: `DC2DBA0E8FBE7FE4764DB313DB090EBE5FF0C4FA821B90C77017BE6DCFD6DE8C`
- signing: `apksigner` v2 verification passed
- badging: compileSdk/targetSdk 36, minSdk 26

This is a valid staging build, but it is not production evidence: the Quick Tunnel has no uptime guarantee and the emulator still did not register an ADB device. Clean install, runtime screen map, physical-device QA and Shelly sign-off remain blocked.

After removing only the two empty Flutter lock files with elevated permission, `flutter test test/unit/app_constants_test.dart --no-pub` passed `3/3`. A fresh bounded `flutter analyze --no-pub` run still stopped at `Analyzing app...` after approximately 60 seconds; analyzer gate remains `BLOCKED`.

## Runtime smoke on emulator (2026-09-21)

The API 36 emulator became available as `emulator-5554` (physical display 1080x2424, density 420). The staging APK was clean-installed successfully; package verification reported `com.bes.vinbatery`, version `1.1.5`, code `115`.

Evidence captured:

- `01-cold-start.png`: cold start with Android notification permission prompt.
- `02-login-after-permission.png`: login screen after dismissing permission prompt.
- `05-fields-filled.png`: valid test credentials entered; password is masked.
- `07-login-after-wait.png`: dashboard opened from Firebase/cache while API tunnel was unavailable.
- `09-charging-tab.png`: charging screen, AI/scheduled tabs and SOC controls visible.
- `10-scheduled-charging.png`: scheduled charging choices (no relay command issued).
- `11-history.png`: history screen with empty recent charging data.
- `12-settings.png`: settings menu with vehicle, Shelly, AI and notification sections.
- `13-system-settings.png`: system settings detail.
- `14-notification-center.png`: notification center list.

No application `FATAL EXCEPTION` or ANR signature was found in the sampled logcat. The tunnel hostname subsequently failed DNS resolution inside the emulator; logcat recorded normalized `SOCKET_EXCEPTION` messages and the UI showed a non-blocking server status strip plus sync interruption card. This proves the offline/cache branch is reachable, but not successful online sync. The runtime critical-flow gate remains `BLOCKED` until the tunnel is stable or a real HTTPS staging service is used.

Observed UX issue during offline navigation: two sync interruption cards were rendered at the same top position (`Kết nối bị gián đoạn` and `Kết nối Shelly chưa ổn định`). Dismissing one left another card in the same location, and the stack obscured the first content block. Evidence: `15-dismiss-error-card.png`, `16-dismiss-second-card.png`, and `settings2.xml`. This is a P1 candidate for connection-error deduplication/stack layout, not a crash.
