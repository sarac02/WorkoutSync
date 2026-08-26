import OverlayKit
import RelayKit
import SwiftUI

/// Apple TV has no WatchConnectivity pairing, so this target never talks to
/// TransportKit directly -- it joins the iPhone's Multipeer relay instead and
/// hands the same `WorkoutOverlayTimeline`/`VideoOverlayContainer` used on
/// iPhone a `WorkoutRelayClient` as its sample source.
struct ContentView: View {
    @State private var pairingCodeInput = ""
    @State private var relayClient: WorkoutRelayClient?

    var body: some View {
        if let relayClient {
            connectedView(relayClient)
        } else {
            pairingView
        }
    }

    private var pairingView: some View {
        VStack(spacing: 24) {
            Text("Enter the pairing code shown on your iPhone")
                .font(.title3)
            TextField("0000", text: $pairingCodeInput)
                .frame(maxWidth: 240)
                .multilineTextAlignment(.center)
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Button("Connect") {
                let client = WorkoutRelayClient(displayName: "Apple TV", pairingCode: pairingCodeInput)
                client.start()
                relayClient = client
            }
            .disabled(pairingCodeInput.count != 4)
        }
        .padding()
    }

    @ViewBuilder
    private func connectedView(_ relayClient: WorkoutRelayClient) -> some View {
        if let videoURL = Bundle.main.url(forResource: "sample_workout", withExtension: "mp4") {
            VideoOverlayContainer(videoURL: videoURL, sampleSource: relayClient)
                .onDisappear { relayClient.stop() }
        } else {
            ContentUnavailableView(
                "Add a workout video",
                systemImage: "video.badge.plus",
                description: Text("Drop an mp4 named sample_workout.mp4 into the WorkoutSyncTV target.")
            )
        }
    }
}
