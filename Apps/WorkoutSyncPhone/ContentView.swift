import OverlayKit
import RelayKit
import SwiftUI
import TransportKit
import UIKit

struct ContentView: View {
    @State private var isRelayingToTV = false
    @State private var useSimulatedData = true
    @State private var relayHost = WorkoutRelayHost(displayName: UIDevice.current.name)
    @State private var simulatedSource = SimulatedWorkoutSampleSource()

    private var activeSampleSource: any WorkoutSampleSource {
        useSimulatedData ? simulatedSource : WorkoutTransport.shared
    }

    var body: some View {
        NavigationStack {
            Group {
                if let videoURL = Bundle.main.url(forResource: "sample_workout", withExtension: "mp4") {
                    VideoOverlayContainer(videoURL: videoURL, sampleSource: activeSampleSource)
                        .id(useSimulatedData) // force a fresh timeline when the source switches
                } else {
                    ContentUnavailableView(
                        "Add a workout video",
                        systemImage: "video.badge.plus",
                        description: Text("Drop an mp4 named sample_workout.mp4 into the WorkoutSyncPhone target to preview the live overlay.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // On: fabricated data so the overlay is visible without
                    // a real Watch (the Simulator can't produce real
                    // WatchConnectivity/HealthKit data). Off: the real
                    // WorkoutTransport, for a physical Watch-paired iPhone.
                    Toggle("Simulated Data", isOn: $useSimulatedData)
                        .toggleStyle(.button)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Toggle("Relay to Apple TV", isOn: $isRelayingToTV)
                            .toggleStyle(.button)
                            .onChange(of: isRelayingToTV) { _, isOn in
                                if isOn {
                                    relayHost.start(sampleSource: activeSampleSource)
                                } else {
                                    relayHost.stop()
                                }
                            }
                        if isRelayingToTV {
                            // The TV won't join without this code -- see
                            // WorkoutRelayHost.pairingCode.
                            Text("Enter on Apple TV: \(relayHost.pairingCode)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
