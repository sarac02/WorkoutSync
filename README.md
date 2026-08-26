# WorkoutSync

WorkoutSync is a portfolio project that recreates how Apple Fitness+ works under the hood. A workout on Apple Watch gets streamed live to a video playing on iPhone, and relayed on to Apple TV, with heart rate, calories, and an activity ring animated on top of the video in real time.

It's built around the two things a Fitness+ client engineer actually deals with: getting workout data between devices reliably, and rendering that live data as a smooth video overlay.

## Architecture

```mermaid
flowchart TB
    subgraph Shared["Shared foundation (pure Swift/C++, no Apple frameworks)"]
        direction LR
        WM["WorkoutModel<br/>sample type + protocol"]
        WC["WireCodec<br/>wire format + clock offset math"]
    end

    subgraph Watch["⌚ Apple Watch"]
        direction TB
        HK["HKWorkoutSession /<br/>HKLiveWorkoutBuilder"]
        CG["CaptureGuard<br/>plausibility gate"]
        WT["WorkoutTransport"]
        HK --> CG --> WT
    end

    subgraph Phone["📱 iPhone"]
        direction TB
        WCT["WCTransportSession<br/>CTransport, Obj-C++"]
        OTP["WorkoutOverlayTimeline"]
        VOCP["VideoOverlayContainer"]
        RH["WorkoutRelayHost<br/>+ pairing code"]
        WCT --> OTP --> VOCP
        WCT --> RH
    end

    subgraph TV["📺 Apple TV"]
        direction TB
        RC["WorkoutRelayClient<br/>+ own clock sync"]
        OTT["WorkoutOverlayTimeline"]
        VOCT["VideoOverlayContainer"]
        RC --> OTT --> VOCT
    end

    WT ==>|"WatchConnectivity<br/>binary + clock sync"| WCT
    RH ==>|"MultipeerConnectivity<br/>tagged + clock sync"| RC

    Shared -.-> Watch
    Shared -.-> Phone
    Shared -.-> TV

    classDef watch fill:#eef6ff,stroke:#3b7dd8,color:#1a3a5c
    classDef phone fill:#eafbea,stroke:#3fa34d,color:#1d4a24
    classDef tv fill:#f5eefc,stroke:#8a4fd1,color:#3d2160
    classDef shared fill:#f4f4f4,stroke:#888,color:#333
    class HK,CG,WT watch
    class WCT,OTP,VOCP,RH phone
    class RC,OTT,VOCT tv
    class WM,WC shared
    style Watch fill:#f8fbff,stroke:#3b7dd8,stroke-width:1px
    style Phone fill:#f6fcf6,stroke:#3fa34d,stroke-width:1px
    style TV fill:#faf7fd,stroke:#8a4fd1,stroke-width:1px
    style Shared fill:#fafafa,stroke:#999,stroke-width:1px,stroke-dasharray: 4 3
```

Every device follows the same pattern: receive the data, correct for the clock difference between devices, smooth it out, then render it. The Watch is the only real source of data. The iPhone and Apple TV are both just consumers of that same corrected stream, which is why they share the same rendering code (`OverlayKit`).

`CaptureGuard` is worth calling out on its own: it checks incoming heart rate and calorie readings for physically implausible jumps before they get transmitted or shown on screen. It never touches what HealthKit actually saves though. That stays untouched, since editing someone's real health data because a reading looked odd would be wrong.

## Setup and requirements

- Full Xcode, not just Command Line Tools. Install from the Mac App Store or developer.apple.com, then run `sudo xcode-select -s /Applications/Xcode.app` and open it once.
- Open `WorkoutSync.xcodeproj` and set your Team in each target's Signing and Capabilities tab.
- If you change anything structural, edit `project.yml` and run `xcodegen generate` instead of editing the Xcode project by hand.
- A workout video named `sample_workout.mp4` goes in the `WorkoutSyncPhone` and `WorkoutSyncTV` targets.

## Running it

- **iPhone**: use the `WorkoutSyncPhone` scheme. The Simulator is fine for checking the UI, but you need a real Watch paired iPhone to see live data, since WatchConnectivity and HealthKit don't behave the same way in the Simulator. A "Simulated Data" toggle feeds fake data through the real pipeline if you don't have a Watch on hand.
- **Watch**: it's bundled into the `WorkoutSyncPhone` build and installs automatically on a paired iPhone.
- **Apple TV**: use the `WorkoutSyncTV` scheme. Turn on "Relay to Apple TV" on the iPhone, then enter the code it shows you into the TV's connect screen.

## Tests conducted

Every package has its own test suite and all of them pass. Run `swift test` inside any package folder, or Cmd+U in Xcode to run everything.

What's actually covered:
- The wire format encodes and decodes samples correctly and rejects bad data.
- The clock sync logic recovers the right time offset between two devices.
- The video overlay interpolates smoothly between samples instead of jumping.
- The Watch to TV relay's pairing code and clock sync both work as expected.
- CaptureGuard accepts normal readings and rejects impossible ones, like a heart rate spike that isn't physically possible, without messing up the readings that come after it.

Testing on real builds, not just checking that things compile, caught real bugs along the way: a watchOS API that silently doesn't exist on watchOS, a missing framework link, a missing companion app identifier that blocked installs entirely, and two real data races that would have caused intermittent crashes on an actual device.

## Limitations

- Nothing has run on physical hardware yet, only Simulators. A real Watch, iPhone, and Apple TV may behave differently.
- GymKit isn't accessible to regular developers. Apple restricts it to certified gym equipment manufacturers, so there's no real "connect to a treadmill" feature here.
- CaptureGuard uses simple fixed thresholds, not an actual physiological model.
- The clock sync between iPhone and Apple TV takes a couple of seconds to kick in after they connect.
