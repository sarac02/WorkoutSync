# WorkoutSync

A portfolio project modeled on how Apple Fitness+ actually works end to end:
a live workout on Apple Watch, streamed in real time to a video player on
iPhone/iPad (and relayed onward to Apple TV), rendered as animated overlays
— a live heart-rate ticker, a Burn Bar, a closing Activity Ring — synced to
the video's own timeline rather than just "whenever the last message arrived."

It's built to mirror the two things a Fitness+ client engineer actually
touches: **low-level device-to-device communication**, and **rendering /
animating that data as a video overlay**, across Watch, iPhone, iPad, and
Apple TV.

## Architecture

```
 Apple Watch                    iPhone / iPad                  Apple TV
┌───────────────┐   WatchConnectivity   ┌──────────────────┐  Multipeer  ┌──────────────────┐
│ HKWorkoutSession/│ ───────────────────▶│ WCTransportSession│────────────▶│ WorkoutRelayClient│
│ HKLiveWorkoutBuilder                   │  (CTransport,     │  (relayed   │  (RelayKit)       │
│  → WorkoutTransport                    │   Obj-C++)        │   1 hop)    │        │          │
└───────────────┘                        │        │          │            │        ▼          │
                                          │        ▼          │            │ WorkoutOverlayTimeline
                                          │ WorkoutOverlayTimeline          │        │          │
                                          │        │          │            │        ▼          │
                                          │        ▼          │            │ VideoOverlayContainer
                                          │ VideoOverlayContainer           └──────────────────┘
                                          └──────────────────┘
```

Five local Swift packages, split by platform reach rather than by feature —
this is what let most of it actually get built and run on a Mac with no iOS
SDK at all (see "What's been verified" below):

- **WorkoutModel** — the shared value type. `WorkoutSample` (timestamp, heart
  rate, active energy, distance, source device name) and the
  `WorkoutSampleSource` protocol. Pure Swift/Foundation, no platform-specific
  dependency at all — everything else depends on this instead of on each
  other directly.
- **WireCodec** — the wire protocol as pure C++ behind a plain C API: a
  fixed-size binary layout for a sample (`wc_encode_sample`/
  `wc_decode_sample`, far cheaper than a dictionary/NSCoding round trip for
  something sent several times a second), and a rolling-median clock-offset
  estimator (`wc_clock_estimator_*`) that turns a series of round-trip
  timing probes into an estimate of *(this device's clock) − (counterpart's
  clock)*. No Foundation, no Apple frameworks — this is what makes it
  testable anywhere.
- **TransportKit** — the actual Watch ↔ iPhone transport. `CTransport`
  (Obj-C++) wraps `WCSession`: it picks the lowest-latency send path
  available, frames messages with a 1-byte tag so one channel carries both
  live samples and clock-sync pings, and calls into WireCodec for the
  encode/decode and offset math. `TransportKit` (Swift) wraps that behind
  `WorkoutTransport`, an `AsyncStream<WorkoutSample>`. This is the one
  package that *requires* WatchConnectivity, so it only targets iOS/watchOS.
- **OverlayKit** (iOS + tvOS + macOS) — the rendering layer.
  `WorkoutOverlayTimeline` buffers the last dozen samples and linearly
  interpolates between them to produce a smooth 30fps signal from a feed
  that really only updates once a second or so — this is what stops the
  heart-rate number from visibly stuttering. `VideoOverlayContainer`
  composites an `AVPlayer` with `HeartRateTickerView`, `BurnBarView`, and
  `ActivityRingsOverlayView` on top.
- **RelayKit** (iOS + tvOS + macOS) — the reason Apple TV can show any of
  this at all. Apple TV has no Watch pairing, so `WorkoutRelayHost` (runs on
  iPhone) rebroadcasts every sample it gets from the Watch to the TV over
  `MultipeerConnectivity`, and `WorkoutRelayClient` (runs on tvOS) receives
  it and hands it to the exact same `OverlayKit` UI the iPhone uses.
- **CaptureGuard** (all platforms) — a live-data plausibility gate, running
  on the Watch before a reading is ever transmitted. See "Does this improve
  data accuracy?" below for why it exists and, just as importantly, what it
  deliberately does *not* do.

**Apps/** has three thin app targets (`WorkoutSyncWatch`, `WorkoutSyncPhone`,
`WorkoutSyncTV`) that wire the packages together. The Watch app runs a real
`HKWorkoutSession`/`HKLiveWorkoutBuilder`, passes each reading through
`CaptureGuard`, and streams the result out via `WorkoutTransport`.

## Does this improve data accuracy?

Short answer: it improves what gets **shown live and relayed**, not what
HealthKit **permanently records** — and that distinction is deliberate, not
a limitation I ran out of time to fix.

`HKWorkoutBuilder.finishWorkout` saves whatever the Watch's actual sensors
and HealthKit's own algorithms produced. This project never touches that —
silently editing a user's permanent health record because a reading looked
weird would be actively wrong, since a noisy-but-real reading still belongs
in their history.

What `CaptureGuard` (see `Packages/CaptureGuard`) does instead is gate the
*live, client-side* copy of the data — the numbers this app chooses to
transmit to another device and animate on screen right now:

- **`HeartRateQualityGate`** rejects readings outside plausible human range
  outright, and rejects a rate of change no real heart can produce between
  two consecutive readings (default ceiling: 60 BPM/s — generous enough to
  let a real sprint-start spike through, tight enough to catch a
  loose-watch-band sensor glitch). A rejected reading doesn't poison future
  comparisons — the next real reading is still compared against the last
  *good* one.
- **`CumulativeMetricGuard`** holds active energy/distance at their last
  value if a new reading would make them go backwards — cumulative metrics
  shouldn't decrease, and a decrease almost always means an out-of-order
  HealthKit callback, not the user's calorie burn reversing.
- **`SensorDropoutMonitor`** flags when heart-rate updates have gone quiet
  longer than a real sensor should during an active workout, so the Watch UI
  can show "checking heart rate…" instead of silently freezing on a stale
  number as if nothing's wrong.

This is still fundamentally a **client-side rendering/UX concern**, the same
territory as the rest of this project — it makes the *live experience*
trustworthy, not the sensor science. Actually improving how correctly the
Watch measures heart rate and calories in the first place (PPG signal
processing, motion-artifact rejection, calorie-estimation algorithms) is a
different, real engineering problem, owned by Apple's Health/Sensing side,
not the Fitness+ client team this project is aimed at.

## What's been verified, and how

This started out scaffolded on a Mac with only the Xcode Command Line Tools
(no full Xcode, no iOS/watchOS/tvOS SDKs, no `XCTest.framework`), which meant
the first pass could only prove `WorkoutModel`/`WireCodec`/`OverlayKit`/
`RelayKit` compiled on plain macOS, plus a throwaway `swift run` harness
exercising the core logic without XCTest. Full Xcode is now installed, and
everything has since been rebuilt and tested for real:

- **All three app targets build clean** against the actual iOS/watchOS/tvOS
  Simulator SDKs (`xcodebuild build`, not just a syntax check).
- **All six packages' test suites genuinely pass**, including
  `TransportKitTests` (needs an iOS/watchOS destination since it links
  `CTransport`/WatchConnectivity) run via `xcodebuild test`.
- **The Phone app was actually installed and launched in the iOS
  Simulator**, screenshotted, and confirmed rendering the live overlay
  correctly (heart-rate ticker, activity ring, Burn Bar all animating over
  the video) — fed by a `SimulatedWorkoutSampleSource` since WatchConnectivity/
  HealthKit don't produce real data in the Simulator.
- This process caught several real bugs that a "should compile" review
  would have missed: a cross-target header import that doesn't work the way
  it looks like it should, `CACurrentMediaTime()` being unavailable on
  watchOS (which would have meant the Watch and iPhone silently disagreeing
  about what clock they're on), a missing explicit framework-link setting
  for WatchConnectivity, a missing `WKCompanionAppBundleIdentifier` that
  blocked installation entirely, and a video view that wasn't actually
  filling the screen. All fixed and reverified.
- A later manual review turned up two genuine data races, not just
  build-time bugs: `WorkoutOverlayTimeline` spawned two unstructured
  `Task`s (one ingesting samples, one ticking the render loop) that both
  touched a plain `Array` with no synchronization — fixed by making the
  class `@MainActor`-isolated. And `WCClockOffsetEstimator`'s underlying
  `std::deque` was written from whatever queue WatchConnectivity delivers
  its reply-handler callback on, while `WorkoutTransport.estimatedClockOffset`
  is a public property readable from any thread an app calls it from — fixed
  by adding a mutex in `WireCodec.cpp`. Both were re-verified with the full
  test suite and a clean rebuild of all three app targets afterward.

## Setup

1. **Requires full Xcode.app**, not just Command Line Tools — install it
   from the Mac App Store, or from
   [developer.apple.com/download/applications](https://developer.apple.com/download/applications)
   if you need a specific version (requires an Apple ID). After installing,
   run `sudo xcode-select -s /Applications/Xcode.app` and open Xcode once to
   finish first-launch component installation. I can't do this step for
   you — it needs your Apple ID sign-in.
2. Open `WorkoutSync.xcodeproj` and let Xcode resolve the five local Swift
   packages. In each app target's Signing & Capabilities tab, set your own
   Team (`project.yml` uses a placeholder bundle ID prefix,
   `com.saraworkoutsync`). If you change anything structural, edit
   `project.yml` and re-run `xcodegen generate` rather than hand-editing the
   `.xcodeproj`.
3. Add a video file named `sample_workout.mp4` to the `WorkoutSyncPhone` and
   `WorkoutSyncTV` targets (any local mp4 works — this project has no
   licensed Fitness+ content). Without it, both apps show a placeholder
   view instead of crashing.

## Running it

- **iPhone/iPad**: select the `WorkoutSyncPhone` scheme, run on a Simulator
  to check the UI/overlay layout, but run on a **real, paired iPhone** to see
  live data — WatchConnectivity and HealthKit don't behave like the real
  thing in the Simulator.
- **Apple Watch**: it's embedded in the `WorkoutSyncPhone` scheme's build
  (see `project.yml`'s `embed: true` dependency) — building and running
  `WorkoutSyncPhone` on a physical, Watch-paired iPhone installs the Watch
  app too. Start the workout from the Watch app; the iPhone app should start
  showing live heart rate/energy within a few seconds.
- **Apple TV**: select the `WorkoutSyncTV` scheme, run on a real Apple TV
  (or the tvOS Simulator for layout only — Multipeer relay needs a real
  network). On the iPhone app, toggle "Relay to Apple TV" while a workout is
  active; the TV should pick up the same live metrics within a couple of
  seconds of joining.
- If you don't have an Apple Watch or Apple TV to test against, the honest
  fallback is the iPhone app alone with the placeholder-video screen — the
  overlay UI and interpolation logic can be exercised directly by feeding
  `WorkoutOverlayTimeline` a fake `WorkoutSampleSource` (see the harness
  approach in `OverlayKitTests`).

## Running the tests

Once Xcode is installed:

- **Per-package, from the command line**: `cd Packages/<Name> && swift
  test` — works today for `WorkoutModel`, `WireCodec`, `OverlayKit`, and
  `RelayKit`. `TransportKit`'s tests need an iOS/watchOS destination, so run
  those from Xcode instead (see below).
- **From Xcode**: open `WorkoutSync.xcodeproj`, pick any scheme, and hit
  ⌘U — this runs each package's `Tests/` target through Xcode's test
  navigator, including `TransportKitTests` (which needs the iOS/watchOS SDK
  Xcode provides).
- **From the command line against a simulator** (useful for CI):
  `xcodebuild test -project WorkoutSync.xcodeproj -scheme WorkoutSyncPhone
  -destination 'platform=iOS Simulator,name=iPhone 16'`

What each suite actually covers:

| Package | Tests | What they check |
|---|---|---|
| WorkoutModel | `WorkoutSampleTests` | Codable round trip, field-wise equality, a stub `WorkoutSampleSource` |
| WireCodec | `WireCodecTests` | Binary encode/decode round trip + truncated-buffer rejection; clock estimator recovers a known offset and resists one outlier probe |
| OverlayKit | `WorkoutOverlayTimelineTests` | Linear interpolation between bracketing samples, holding the last value past the newest sample (no extrapolation), buffer eviction past capacity, out-of-order ingestion |
| RelayKit | `RelayKitTests` | JSON wire-format round trip + garbage-data rejection; the Multipeer `serviceType` constant satisfies MultipeerConnectivity's length/charset constraints |
| TransportKit | `WorkoutSampleWireTests` | `WorkoutSample` round-trips through the Obj-C `WTSample`/`packedData` bridge unchanged |
| CaptureGuard | `HeartRateQualityGateTests`, `CumulativeMetricGuardTests`, `SensorDropoutMonitorTests` | Accepts plausible gradual changes, rejects an impossible instant spike and out-of-range readings without poisoning later comparisons; cumulative metrics hold instead of going backwards; dropout is detected after the threshold and cleared by a fresh sample |

## Known simplifications / honest gaps

Three gaps that were flagged here in an earlier pass have since been fixed
for real, not just documented differently:

- ~~The iPhone→Apple TV relay hop doesn't run its own clock sync~~ — it now
  does. `WorkoutRelayClient` runs the same round-trip probing pattern as
  `WCTransportSession` (send a ping, get an echo with the host's timestamp,
  compute the offset via `WireCodec`'s `ClockOffsetEstimator`) over the
  Multipeer link itself, and re-timestamps incoming relayed samples using
  that measured offset instead of just stamping them with local receipt
  time. It still falls back to receipt-time stamping for the few seconds
  before the first sync estimate lands (e.g. right after connecting).
- ~~`WorkoutRelayHost` accepts any incoming Multipeer invitation
  unconditionally~~ — it now requires a 4-digit pairing code. The host
  generates one on `init` (`WorkoutRelayHost.pairingCode`, shown in the
  iPhone UI once relaying is toggled on) and only accepts an invitation
  whose context matches it; the TV app now has a code-entry screen before it
  ever tries to connect.
- **`CaptureGuard`'s plausibility thresholds are still simple, tunable
  heuristics**, not a physiological model — but they're no longer a single
  symmetric number. `HeartRateQualityGate` now uses separate rise/fall
  ceilings (default 60 BPM/s rise, 30 BPM/s fall), reflecting that real
  heart-rate recovery is measurably slower than heart-rate onset kinetics —
  a rapid *drop* is less physiologically plausible than an equally rapid
  *rise*. Still a heuristic: real HR-artifact rejection in production would
  likely also cross-check against motion data (accelerometer) to
  distinguish "sensor glitch" from "user actually just sprinted."
- **GymKit is not a public third-party API.** Apple restricts it to MFi-
  certified gym equipment manufacturers, so there's no real "connect to a
  treadmill" path here. If you want to demo the idea, the honest framing is
  a simulated equipment peer (a `Timer`-driven fake publishing pace/incline
  through `RelayKit`'s transport), clearly labeled as a simulation — not an
  integration with real GymKit.
- The Burn Bar's reference value and the ring's goal energy are passed in as
  plain numbers; a real app would source them from the workout's own
  metadata.
- `sample_workout.mp4` is a synthetic SMPTE-style test pattern generated
  with ffmpeg, not real workout footage — there's no licensed Fitness+
  content here.
- **Nothing here has run on physical hardware yet** — only Simulators.
  Real-device WatchConnectivity/HealthKit/Multipeer behavior (reachability
  flakiness, background delivery timing, actual Bluetooth/Wi-Fi conditions)
  can only really be validated on a real Watch, iPhone, and Apple TV.
