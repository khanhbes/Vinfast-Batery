# UI/UX layout fixes — 2026-09-08

## Changes verified in this pass

- Home: summary, quick-action and achievement cards use adaptive columns and equal height within each row. Large text reduces columns instead of forcing a fixed card height.
- Home: missing efficiency data wraps below the heading. Full-screen scrolling previously reproduced horizontal overflow (130px at 320dp, 450px with 2x text); the regression now passes.
- Home: failed decorative network image leaves a usable card background.
- Statistics: summary cards grow with content; labels/subtitles can wrap. Loading skeleton previously overflowed vertically by 11px at 320dp; it now uses adaptive rows too.
- Shared empty/error states scroll in short viewports; action buttons have a minimum 48dp height rather than a fixed 44dp height.
- Login/Register: submit buttons grow with text; the login registration link respects system text scaling.

## Verification

New regression suites: `responsive_cards_test.dart`, `home_layout_test.dart`, `statistics_layout_test.dart`, `auth_layout_test.dart`.

- Card matrix: widths 320/360/375/412/768dp, text scales 1/1.3/2, mixed-length labels and optional subtitles. Tests assert equal width, equal row height and containment.
- Empty/error: 320x240dp, 2x text, scroll to and activate the action.
- Home: empty vehicle state, 320x568dp, 1x/2x text, scroll across the page, network image unavailable.
- Statistics: loading and summary states with fixture statistics and empty charge history, 320x568dp, 1x/2x text.
- Auth: 320/412dp, 2x text, simulated 240dp keyboard inset, submit action reachable.
- Existing battery-gauge QA tests: 3 passed.
- Existing widget suite run during implementation: 48 passed, 2 failed in Smart Charging (pending timer and unexpected `Tiêu chuẩn` label). These are also listed in the earlier audit baseline; they remain unresolved in this pass.
- Targeted analyzer: no compilation errors reported; existing unused declarations/deprecation/style diagnostics remain.
- `git diff --check`: passed.

## Limits and remaining checks

This is not certification that every app screen is free of UI/UX defects. No Android device or emulator was connected (`adb devices -l` returned an empty list). No device screenshots, TalkBack or visual inspection of authenticated live-data screens was completed.

Remaining coverage includes Dashboard, Battery Monitor, charts with real histories, AI detail/settings screens, vehicle sheets, notification flows, live maps, landscape, VI/EN and both themes. The Statistics test above does not exercise populated charts, and the Home test does not exercise an AI range prediction with a real vehicle.

Production charging/auth/data algorithms were not changed. No APK was built or installed in this pass.
