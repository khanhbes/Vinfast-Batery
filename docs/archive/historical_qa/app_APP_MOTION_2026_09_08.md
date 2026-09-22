# App motion refinement

## Direction

Follow the frontend-skill's restrained app motion guidance: preserve the cockpit layout and content hierarchy, use short entrances and clear press/selection feedback, and avoid ornamental continuous effects. No images or new dependencies are needed.

## Applied

- Main navigation: 260 ms fade/6 px slide on tab selection without replacing tab state. Hidden tab tickers are muted; the global charging overlay stays outside the transition. Selected navigation icons gain subtle scale without changing layout width.
- Shared AppReveal: 260 ms entrance, at most 240 ms stagger, small pixel-based displacement; content remains visible and interactive throughout. Rebuilding the widget does not restart its entrance, and no delay timers are added.
- Overview/Home, login, registration, statistics, More, and settings use the common entrance system. Existing consumers of appFadeSlideIn in maintenance/garage also inherit the shared behavior.
- Login/registration: restrained logo reveal instead of elastic bounce; error messages no longer shake.
- PremiumCard: 180 ms press response, keyboard activation through InkWell, and no scale animation when reduced motion is enabled.
- Battery gauge: 600 ms decorative arc interpolation; displayed SOC is the actual input immediately, including during updates. Reduced motion snaps the arc to its target.
- Shared reveal/scale helpers, tab transitions, card press animation and gauge respect system reduced motion. Older feature-specific looping controllers have not all been migrated.

## Verification

- 23 targeted widget tests passed across motion, auth, home, statistics, gauge QA and AI Studio.
- Core motion/navigation analysis: no issues found.
- Wider touched-screen analysis: no errors; existing Home/Auth/Statistics warnings and lint notices remain. Test-only deprecated TickerMode access was subsequently updated.
- git diff --check passed.
- No real-device FPS/battery profiling or visual acceptance recording performed; no APK build or deployment in this pass.

## Device acceptance

Check tab switching and back navigation, scroll restoration, keyboard focus, reduced-motion toggling, battery updates and OFF-button responsiveness. Profile on a lower-end Android device before asserting a 60/120 fps target. The global charging control must never be hidden behind entrance animation.
