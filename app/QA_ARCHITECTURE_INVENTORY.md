# VinFast Battery App — QA Architecture & Traceability Inventory

**Audit Target:** `app/` (Flutter Android)  
**Audit Baseline Commit:** `ba9df98` (Branch: `qa/app-master-audit-2026-09-07`)  
**Specification:** `VINFAST_BATTERY_APP_MASTER_QA_UIUX_AUDIT.md` & `PLAN.md`  
**Date:** 2026-09-07  
**Status:** Frozen Baseline for Comprehensive QA & UI/UX Audit  

---

## 1. System Overview & Entry Points

- **Primary Entrypoint:** `app/lib/main.dart`
  - Initializes `WidgetsFlutterBinding.ensureInitialized()`.
  - Initializes Firebase via `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
  - Loads dynamic server configuration (`custom_api_base_url`) from `SharedPreferences`.
  - Configures global error handling: `FlutterError.onError` redirected to `AppErrorReporter.recordFlutterError` and `PlatformDispatcher.instance.onError` to `AppErrorReporter.recordError`.
  - Wraps root in `ProviderScope` (Riverpod 2.6.1).
- **Application Shell:** `app/lib/app.dart` (`VinfastBatteryApp`)
  - ConsumerWidget configuring `MaterialApp`.
  - Themes: `AppTheme.darkTheme` (default Dark Luxury Cockpit `#0B0E0D`) and `AppTheme.lightTheme`.
  - ThemeMode driven by `themeModeProvider`.
  - Localization: `AppLocalizations.supportedLocales` (`vi`, `en`), delegates from `flutter_localizations` and `AppLocalizations.delegate`.
  - Navigation: `AppNavigation.onGenerateRoute`, `navigatorKey: AppNavigation.navigatorKey`.
  - Home: `const AuthGate()`.

---

## 2. State Management Architecture

State management is powered by **Riverpod 2.6.1**:

| Category | Providers | File Location | Purpose |
|---|---|---|---|
| **Auth** | `authServiceProvider`, `authStateChangesProvider`, `currentUserProvider` | `lib/core/providers/auth_provider.dart` | Firebase Auth streaming and session identity |
| **Vehicle** | `vehiclesStreamProvider`, `selectedVehicleProvider`, `vehicleContextControllerProvider` | `lib/core/providers/vehicle_provider.dart` | Vehicle list, active vehicle switching |
| **Battery / Telemetry** | `batteryStateStreamProvider`, `latestTelemetryProvider` | `lib/core/providers/battery_provider.dart` | SOC, voltage, power, temperature live stream |
| **Smart Charger** | `smartChargingControllerProvider`, `smartChargerStatusProvider`, `chargerTelemetryStreamProvider` | `lib/features/smart_charging/` | Relay state, target SOC, schedule, power controls |
| **AI / Prediction** | `rangePredictionProvider`, `chargingEtaProvider`, `personalAiProfileProvider` | `lib/features/ai/`, `lib/features/smart_charging/` | AI model predictions, fine-tuning status |
| **Theme & UI** | `themeModeProvider`, `localeProvider` | `lib/core/providers/app_state_provider.dart` | Dark/light theme, language selection |
| **Notifications** | `unreadNotificationCountProvider`, `notificationListProvider` | `lib/features/notifications/` | In-app alerts, charging thresholds |

---

## 3. Navigation & Screen Catalog

All routes are declared and dispatched through `AppNavigation` (`lib/navigation/app_navigation.dart`):

| Route Name | Screen Widget | Path / Description |
|---|---|---|
| `/` | `AuthGate` | Auth routing gate (Login vs Main Navigation) |
| `/login` | `LoginScreen` | Firebase email/password authentication |
| `/register` | `RegisterScreen` | New account onboarding |
| `/home` | `AppNavigation` (Shell) | Bottom navigation bar host with 5 tabs |
| *Tab 0* | `HomeScreen` | Battery gauge, quick actions, range estimate |
| *Tab 1* | `DashboardScreen` | Fleet metrics, energy stats, power draw |
| *Tab 2* | `BatteryMonitorScreen` | Cell health, voltage curve, temperature |
| *Tab 3* | `TripPlannerScreen` | GPS trip recorder, route planner, live map |
| *Tab 4* | `MoreScreen` | Menu hub to secondary tools & settings |
| `/smart-charging` | `SmartChargingControlScreen` | Smart Charger control, relay toggling, target SOC |
| `/smart-charging-hub`| `SmartChargerSetupHubScreen` | Shelly setup, LAN/Cloud discovery, QR pairing |
| `/charge-log` | `ChargeLogScreen` | Charge history, kWh stats, cost calculator |
| `/add-charge-log` | `AddChargeLogScreen` | Manual charge record entry |
| `/ai-charging-predictor` | `AiChargingPredictorScreen` | AI ETA estimation, parameter simulation |
| `/ai-models` | `AiModelsScreen` | Deployed ML models, accuracy metrics |
| `/personal-ai-training` | `PersonalAiTrainingDataScreen` | Vehicle-specific ground-truth fine-tuning data |
| `/developer-ai-studio` | `DeveloperAiStudioScreen` | Full dataset inspector, hyperparameter tuner, ping |
| `/statistics` | `StatisticsScreen` | Energy, distance, efficiency charts |
| `/maintenance` | `MaintenanceScreen` | Service intervals, component wear tracking |
| `/notifications` | `NotificationsScreen` | Notification history & safety events |
| `/settings` | `SettingsScreen` | AI settings, appearance, account, developer |
| `/profile` | `ProfileScreen` | User profile & vehicle ownership info |
| `/appearance` | `AppearanceSettingsScreen` | Theme selection (Dark / Light / System) |
| `/vehicle-detail` | `VehicleDetailScreen` | Technical specifications of VinFast models |

---

## 4. Firebase Collections & Ownership Contract

| Collection Path | Read Rule | Write Rule | Sensitive Fields / Owner Security |
|---|---|---|---|
| `users/{uid}` | `auth.uid == uid` | `auth.uid == uid` | `maxActiveVehicles` enforced by security rules |
| `users/{uid}/vehicleChargerBindings/{vId}` | `auth.uid == uid` | `auth.uid == uid` | `containsNoChargerSecrets()` rule prevents key leak |
| `users/{uid}/shellyDevices/{devId}` | `auth.uid == uid` | `write: false` | Backend Admin SDK authoritative write |
| `users/{uid}/chargingTrainingSamples/{sId}` | `auth.uid == uid` | `write: false` | Backend Admin SDK authoritative write |
| `Vehicles/{vehicleId}` | `resource.ownerUid == uid` | `request.ownerUid == uid` | Physical delete prohibited; soft-delete via `isDeleted` |
| `ChargeLogs/{logId}` | `canReadOwned() && notDeleted()` | `ownerUid == uid` | Delete allowed only when session is not `active`/`arming` |
| `ChargeLogs/{logId}/smartChargeTelemetry/{cId}` | `parentLog().ownerUid == uid` | `sessionId == logId && ownerUid == uid` | Append telemetry chunk |
| `TripLogs/{tripId}` | `canReadOwned() && notDeleted()` | `ownerUid == uid` | Route points, distance, consumption |
| `MaintenanceTasks/{taskId}` | `canReadOwned() && notDeleted()` | `ownerUid == uid` | Query must include `.where('isDeleted', isEqualTo: false)` |
| `VinFastModelSpecs/{modelId}` | `allow read: true` | `write: false` | Public catalog (Feliz, Klara, Theon, Evo, etc.) |
| `ShellyCredentialVault/{credId}` | `allow read, write: false` | `write: false` | Vaulted on backend with server-side encryption |

---

## 5. API & Connectivity Architecture

- **Primary Backend:** Flask + Gunicorn / Tailscale Funnel / Localhost
  - Default URL: `https://khanhbes.tailaafca5.ts.net`
  - Fallback / Configurable URLs: LAN (`192.168.x.x:5000`), Android Emulator (`10.0.2.2:5000`), Localhost (`127.0.0.1:5000`).
  - Auth Header: `X-Admin-Key` for developer role; Firebase Bearer token for user operations.
  - Timeout: 12 seconds with graceful `SocketException` & `TimeoutException` interception.
- **Shelly Direct Device Communication:**
  - Protocol: Gen2 RPC over HTTP (`/rpc/Switch.Set`, `/rpc/Switch.GetStatus`, `/rpc/Shelly.GetDeviceInfo`).
  - Dual Path: Cloud API (`/api/shelly/relay`) with automatic LAN Fallback (`http://<device-ip>/rpc/...`).
  - Safety Priority: Manual OFF priority unconditionally executed with zero delay.

---

## 6. Local Storage & Security Audit Boundary

- **`SharedPreferences`:**
  - `custom_api_base_url`: Runtime server IP override.
  - `theme_mode`: 'system' | 'dark' | 'light'.
  - `selected_vehicle_id`: Currently viewed vehicle ID.
  - `offline_dataset_cache_v1`: Offline baseline samples for AI Studio.
  - `offline_finetune_history_v1`: Offline simulated fine-tune evaluations.
- **`FlutterSecureStorage`:**
  - Stored tokens, encryption keys, and credentials.
  - Excluded from system backups via Android backup rules (`android:allowBackup="false"` in manifest).

---

## 7. Five Core Formal State Machines

### 7.1 Authentication State Machine
```text
                  +--------------------------------+
                  |            UNKNOWN             |
                  +---------------+----------------+
                                  |
                                  v
                  +--------------------------------+
                  |           SIGNED_OUT           | <---------------+
                  +---------------+----------------+                 |
                                  |                                  |
                    user submits  |                                  |
                    credentials   v                                  |
                  +--------------------------------+                 |
                  |           SIGNING_IN           |                 |
                  +-------+--------------+---------+                 |
                          |              |                           |
            auth success  |              | auth error                | signOut()
                          v              v                           |
                  +---------------+  +-------------+                 |
                  |   SIGNED_IN   |  | AUTH_ERROR  +-----------------+
                  +-------+-------+  +-------------+
                          |
                          v
                  (Route to /home)
```

### 7.2 Charge Session State Machine
```text
           +-----------------------------------------------+
           |                     IDLE                      | <-------------+
           +-----------------------+-----------------------+               |
                                   | startCharging()                       |
                                   v                                       |
           +-----------------------------------------------+               |
           |                   STARTING                    |               |
           +-------+-------------------------------+-------+               |
                   |                               |                       |
      relay verify |                  failed start |                       |
                   v                               v                       |
           +---------------+               +---------------+               |
           |   CHARGING    |               |  START_ERROR  +---------------+
           +-------+-------+               +---------------+
                   |
                   | stopCharging() / target reached / safety trip
                   v
           +-----------------------------------------------+
           |                   STOPPING                    |
           +-------+-------------------------------+-------+
                   |                               |
       relay verify|                 readback fail |
                   v                               v
           +---------------+               +---------------+
           |   COMPLETED   +-------------> |   STALE_OFF   +---------------+
           +---------------+  save log     +---------------+
```

### 7.3 Smart Charger Relay State Machine (Safety & Readback Enforced)
```text
                       +-------------------------------+
                       |            UNKNOWN            |
                       +---------------+---------------+
                                       |
                         connect/ping  v
                       +-------------------------------+
                       |          OFF / STANDBY        | <---------------------+
                       +---------------+---------------+                       |
                                       |                                       |
                          user tap ON  | (Safety gate: target & limit set)     |
                                       v                                       |
                       +-------------------------------+                       |
                       |       COMMAND_ON_PENDING      |                       |
                       +-------+---------------+-------+                       |
                               |               |                               |
                 readback==ON  |               | timeout / readback!=ON        |
                               v               v                               |
                       +---------------+  +-------------------------------+    |
                       |   RELAY_ON    |  |    READBACK_MISMATCH_ERROR    |    |
                       +-------+-------+  +---------------+---------------+    |
                               |                          |                    |
                               | user tap OFF / safety    | manual OFF         |
                               v                          v                    |
                       +-------------------------------+  |                    |
                       |      COMMAND_OFF_PENDING      |  |                    |
                       +-------+---------------+-------+  |                    |
                               |                          |                    |
                 readback==OFF v                          v                    |
                               +--------------------------+--------------------+
```

### 7.4 Trip Tracking State Machine
```text
                       +-------------------------------+
                       |             IDLE              | <---------------------+
                       +---------------+---------------+                       |
                                       | startTrip()                           |
                                       v                                       |
                       +-------------------------------+                       |
                       |      REQUESTING_LOCATION      |                       |
                       +-------+---------------+-------+                       |
                               |               |                               |
              permission & GPS |               | denied / no GPS               |
                               v               v                               |
                       +---------------+  +-------------------------------+    |
                       |   TRACKING    |  |       LOCATION_BLOCKED        +----+
                       +-------+-------+  +-------------------------------+
                               |
                               | stopTrip() / app killed recovery
                               v
                       +-------------------------------+
                       |      SAVING_TRIP_SUMMARY      |
                       +---------------+---------------+
                                       |
                         write success v
                       +-------------------------------+
                       |           COMPLETED           +-----------------------+
                       +-------------------------------+
```

### 7.5 Offline Data Sync State Machine
```text
                       +-------------------------------+
                       |             CLEAN             | <---------------------+
                       +---------------+---------------+                       |
                                       | local mutation                        |
                                       v                                       |
                       +-------------------------------+                       |
                       |             DIRTY             |                       |
                       +---------------+---------------+                       |
                                       | network detected                      |
                                       v                                       |
                       +-------------------------------+                       |
                       |            SYNCING            |                       |
                       +-------+---------------+-------+                       |
                               |               |                               |
                  server 200 OK|               | network drop / server 5xx     |
                               v               v                               |
                       +---------------+  +-------------------------------+    |
                       |    SYNCED     |  |       SYNC_FAILED_QUEUE       +----+
                       +---------------+  +-------------------------------+
```

---

## 8. Audit Traceability Matrix (59 Checklist Items & 25 Hypotheses)

| ID | Category | Audit Scope / Hypothesis | Code Location | Verification Method | Status |
|---|---|---|---|---|---|
| **CHK-01** | Baseline | Verify clean pub get, analyzer, and test run | Workspace root | `flutter test`, `flutter analyze` | Baseline Tracked |
| **CHK-02** | Baseline | Freeze commit SHA & ensure dirty worktree documented | Git | `git rev-parse HEAD`, `git status` | Tracked (`ba9df98`) |
| **CHK-03** | Auth | Valid credentials sign-in | `login_screen.dart` | Auth Unit & Integration Test | Planned |
| **CHK-04** | Auth | Invalid email / malformed format handling | `login_screen.dart` | Widget test form validator | Planned |
| **CHK-05** | Auth | Wrong password / non-existent user handling | `login_screen.dart` | Mock auth exception test | Planned |
| **CHK-06** | Auth | Rapid multiple tap Login guard (No double request) | `login_screen.dart` | Widget tap debouncing test | Planned |
| **CHK-07** | Auth | Token expiry & silent refresh handling | `auth_provider.dart` | Auth stream test | Planned |
| **CHK-08** | Auth | Sign-out invalidates session & clears memory | `auth_provider.dart` | State clean-up test | Planned |
| **CHK-09** | Auth | Protected screens unreachable via Back after logout | `app_navigation.dart` | Route guard widget test | Planned |
| **CHK-10** | Ownership | User A cannot read User B Vehicle doc | `firestore.rules` | Rules emulator test | Planned |
| **CHK-11** | Ownership | User A cannot write User B ChargeLog | `firestore.rules` | Rules emulator test | Planned |
| **CHK-12** | Ownership | UID strictly derived from `request.auth.uid` | Repositories | Static code audit & test | Planned |
| **CHK-13** | Data | Malformed Firestore doc: missing fields | Data models | Serialization fuzz test | Planned |
| **CHK-14** | Data | Malformed Firestore doc: null / wrong types | Data models | Serialization fuzz test | Planned |
| **CHK-15** | Data | Malformed timestamp handling (Timestamp vs ISO8601) | Data models | Serialization test | Planned |
| **CHK-16** | Battery | SOC invariant: strictly within 0%..100% | `battery_provider.dart` | Invariant property test | Planned |
| **CHK-17** | Battery | Capacity invariant: positive finite value | Vehicle specs | Model sanity test | Planned |
| **CHK-18** | Battery | Voltage / Current / Power: finite & non-NaN | Telemetry models | Math boundary test | Planned |
| **CHK-19** | Battery | Estimated range >= 0 across all states | Range estimators | Boundary test | Planned |
| **CHK-20** | Charge | Double start rapid tap prevention | Charge controller | Concurrency test | Planned |
| **CHK-21** | Charge | Stop session idempotent (No duplicate ChargeLog) | Charge controller | Concurrency test | Planned |
| **CHK-22** | Charge | App killed / background recovery during charging | Background service | Lifecycle test | Planned |
| **CHK-23** | Charger | Safety: Manual OFF always accessible & zero delay | Smart Charger UI | Widget priority test | Planned |
| **CHK-24** | Charger | Safety: Relay ON only reported after verified readback | Smart Charger Service | State machine test | Planned |
| **CHK-25** | Charger | Safety: Readback mismatch triggers error state | Smart Charger UI | Mock mismatch test | Planned |
| **CHK-26** | Charger | Safety: No unintended auto-ON after app/gateway restart | Smart Charger Service | Restart simulation test | Planned |
| **CHK-27** | Charger | Safety: Cloud failover to LAN without double command | Smart Charger Service | Fallback test | Planned |
| **CHK-28** | AI | Input validation: Target SOC > current SOC | AI predictor | Form logic test | Planned |
| **CHK-29** | AI | ETA output invariant: finite duration >= 0 | AI predictor | Output boundary test | Planned |
| **CHK-30** | AI | Heuristics fallback clearly distinguished from ML model | AI Predictor UI | Explanatory badge test | Planned |
| **CHK-31** | AI | AI API timeout/500 graceful fallback without crash | `server_smart_charger_service.dart` | Fault injection test | Planned |
| **CHK-32** | Trip | Android GPS permissions: denied / granted / approximate | Trip planner | Permission mock test | Planned |
| **CHK-33** | Trip | No negative distance / unrealistic jumps | Trip tracking | GPS filter test | Planned |
| **CHK-34** | Trip | Live map rendering with 0, 1, and 1000+ waypoints | Trip live map | Widget stress test | Planned |
| **CHK-35** | Notification | Android notification permission request timing | Notification service | Permission test | Planned |
| **CHK-36** | Notification | Deep-link to deleted object does not crash app | Navigation handler | Deep link test | Planned |
| **CHK-37** | Settings | Persistence: Theme, language, preferred vehicle | Settings provider | SharedPreferences test | Planned |
| **CHK-38** | Update | Semantic version comparison (1.0.10 > 1.0.9) | Update service | SemVer logic test | Planned |
| **CHK-39** | Offline | Launch offline displays cached data gracefully | Home / Dashboard | Offline mock test | Planned |
| **CHK-40** | Offline | Stale cache timestamp indicator shown to user | Battery / Status UI | UI timestamp test | Planned |
| **CHK-41** | Security | No bearer token, password or secret in logs | Logging services | Log audit test | Planned |
| **CHK-42** | Security | SharedPreferences contains no private secrets | Storage layer | Storage audit test | Planned |
| **CHK-43** | Design | Color palette tokens strictly adhere to Cockpit theme | `app_colors.dart` | Static design audit | Planned |
| **CHK-44** | Design | Typography hierarchy: no ad-hoc unscaled styles | `app_theme.dart` | Typography audit | Planned |
| **CHK-45** | Design | Spacing & border radii conform to 8dp/12dp/16dp grid | Widget layer | Design token audit | Planned |
| **CHK-46** | Hierarchy | Visual hierarchy: primary metric visible in < 2s | Home / Dashboard | UX review | Planned |
| **CHK-47** | States | 10-state matrix audit across all primary screens | All screens | State matrix audit | Planned |
| **CHK-48** | Touch | Minimum touch target 44–48 logical pixels for CTAs | All controls | Touch target audit | Planned |
| **CHK-49** | Navigation | No duplicate routes in Navigator stack | `app_navigation.dart` | Route inspection test | Planned |
| **CHK-50** | Form | Keyboard does not obscure focused fields or submit CTA | Auth / Input sheets | Keyboard viewport test | Planned |
| **CHK-51** | Responsive | Responsive layout test: 320x568 (iPhone SE 1) | All screens | Viewport test | Planned |
| **CHK-52** | Responsive | Responsive layout test: 360x640 & 375x812 | All screens | Viewport test | Planned |
| **CHK-53** | Responsive | Responsive layout test: 412x915 & Tablet | All screens | Viewport test | Planned |
| **CHK-54** | TextScale | Text scaling audit: 1.0x, 1.15x, 1.3x, 1.5x, 2.0x | All screens | Dynamic font test | Planned |
| **CHK-55** | L10n | Vietnamese vs English copy completeness & no overflow | ARB & UI | Localization test | Planned |
| **CHK-56** | Theme | Dark & Light theme contrast ratio >= 4.5:1 (WCAG AA) | Color tokens | Contrast audit | Planned |
| **CHK-57** | A11y | TalkBack semantic labels for gauges & charger controls | Widgets | Semantics tester | Planned |
| **CHK-58** | Motion | Reduced Motion setting respected (disable heavy bounce) | `app_motion.dart` | Animation audit | Planned |
| **CHK-59** | Jank | UI Profile: No severe slow frames / memory leak | Core flows | DevTools profile audit | Planned |

---

## 9. High-Risk Hypotheses Traceability Matrix (`APP-H1` to `APP-UX-H25`)

| Hypothesis | Description | Audit Focus & Test Location |
|---|---|---|
| **APP-H1** | Rapid double tap on Start Charge creates two sessions/logs? | `app/test/unit/smart_charging_controller_test.dart` |
| **APP-H2** | Stop/retry charge creates duplicate ChargeLog entry? | `app/lib/features/charge_log/` |
| **APP-H3** | Trip tracking restart creates duplicate trip document? | `app/lib/features/trip_planner/` |
| **APP-H4** | User switch leaves stale user vehicle/data in Riverpod providers? | `app/lib/core/providers/vehicle_provider.dart` |
| **APP-H5** | Vehicle switch with in-flight AI request causes response cross-contamination? | `app/lib/features/ai/` |
| **APP-H6** | SOC > 100% or NaN causes battery gauge or charts to crash? | `app/lib/core/widgets/animated_battery_gauge.dart` |
| **APP-H7** | AI fallback is deceptively displayed as a validated ML model? | `app/lib/features/smart_charging/` |
| **APP-H8** | Stale offline cached SOC is presented as live measured data? | `app/lib/features/home/home_screen.dart` |
| **APP-H9** | Smart Charger UI flips to ON before hardware readback confirms it? | `app/lib/features/smart_charging/` |
| **APP-H10** | Cloud timeout followed by LAN fallback triggers duplicate ON/OFF commands? | `app/lib/data/services/server_smart_charger_service.dart` |
| **APP-H11** | App launch or gateway restart accidentally auto-energizes relay? | `app/lib/features/smart_charging/` |
| **APP-H12** | Emergency manual OFF action is delayed or blocked by pending AI request? | `app/lib/features/smart_charging/` |
| **APP-H13** | Token, password, or Shelly credential leaked into logs or unencrypted storage? | `app/lib/core/utils/` |
| **APP-H14** | Version comparison logic mistakenly evaluates `1.0.10` as smaller than `1.0.9`? | `app/lib/core/services/` |
| **APP-H15** | Text scale 1.5x / 2.0x causes layout overflow in Dashboard or modal sheets? | `app/lib/features/dashboard/` |
| **APP-UX-H16** | Narrow 320dp viewport clips primary CTA buttons or cards? | `app/lib/features/home/` |
| **APP-UX-H17** | Dark mode warning/error states exhibit poor contrast on deep black surfaces? | `app/lib/core/theme/` |
| **APP-UX-H18** | TalkBack screen reader cannot decipher battery gauge or charger control state? | `app/lib/core/widgets/` |
| **APP-UX-H19** | Reduced Motion OS setting is ignored, causing unwanted animation strain? | `app/lib/core/theme/app_motion.dart` |
| **APP-UX-H20** | 5-second polling interval triggers full-screen rebuilds causing visible jank? | `app/lib/features/smart_charging/` |
| **APP-UX-H21** | Fullscreen loading spinner hides emergency manual OFF button? | `app/lib/features/smart_charging/` |
| **APP-UX-H22** | Error copy fails to differentiate between offline state and server error? | `app/lib/core/widgets/error_state.dart` |
| **APP-UX-H23** | Longer Vietnamese strings cause button or chip overflow? | `app/lib/l10n/` |
| **APP-UX-H24** | Pressing system Back after logout re-enters protected screens? | `app/lib/navigation/app_navigation.dart` |
| **APP-UX-H25** | Soft keyboard obscures input fields or submit buttons in bottom sheets? | `app/lib/features/charge_log/` |
