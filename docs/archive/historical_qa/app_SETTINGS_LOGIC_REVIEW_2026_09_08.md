# Settings / Smart Charge / AI Studio — logic review

## Fixed

- Vehicle selector loads actual non-archived vehicles from the shared repository; saves selection through SessionService and selectedVehicleIdProvider. Changing vehicle is guarded against active direct charging and unsaved settings. Display uses persisted vehicle/SOC, not example plates and battery percentages.
- Saving a changed Shelly profile invalidates prior verification before replacing credentials and clears stale drafts. Identical profile saves retain verification. Setup reloads capabilities after saving the new profile.
- Setup server registration respects the encrypted-backup preference. Server upload failure is distinguished from local save success.
- Safe Boot is read-only verification, not a fake hardware switch. Relay test and restart no longer report nonexistent actions as successful. Firmware/MAC/RSSI placeholders are explicitly unavailable.
- AI dataset add/edit is server-first; a failed request does not mutate the displayed dataset or cache. Offline edits are blocked rather than falsely promising future synchronization.
- Removed automatic seeded datasets and fabricated offline fine-tuning results. Training is disabled offline. Manual developer samples are explicitly excluded from training and not marked user-confirmed; IDs no longer wrap every 100 seconds.

## Verification

- 8 tests passed: 2 credential consistency tests and 6 AI Studio widget tests, including offline behavior and responsive populated/results screens.
- Targeted static analysis passed before the final restart/Safe Boot presentation cleanup; final analysis status is in the handoff.
- git diff --check passed.
- No real Firebase writes, Shelly relay/restart commands, model training or deployment performed during testing.

## Remaining verification / design risks

- End-to-end multi-vehicle selection and backup recovery require an authenticated test account and device testing. Local Shelly credentials still use the existing single-profile storage; this review does not add independent profiles per vehicle/account.
- AI cache currently uses the existing shared local cache key; account/server-specific cache isolation needs a dedicated follow-up. No offline mutation queue was introduced.
- Some diagnostic/protection UI remains reference-oriented; this is not a safety certification or complete hardware integration audit.
- Source review is limited to the connected settings flows, not every backend/API/app function.
