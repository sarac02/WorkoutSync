import AVKit
import SwiftUI
import WorkoutModel

/// Composites the workout video with the live metric overlays on top,
/// reading from a `WorkoutOverlayTimeline` so the overlays stay in sync with
/// "now" regardless of how sparsely samples actually arrive.
///
/// `goalEnergy` and `referenceEnergy` stand in for values that would
/// otherwise come from the workout's own metadata (a calorie goal, an
/// average-effort baseline) -- kept as simple parameters here so this view
/// has no dependency on wherever a real app sources that metadata from.
public struct VideoOverlayContainer: View {
    private let player: AVPlayer
    private let sampleSource: any WorkoutSampleSource
    @State private var timeline = WorkoutOverlayTimeline()
    private let goalEnergy: Double
    private let referenceEnergy: Double

    /// - Parameter sampleSource: pass `TransportKit.WorkoutTransport.shared`
    ///   on iPhone, or a `RelayKit.WorkoutRelayClient` on tvOS. Required
    ///   rather than defaulted so OverlayKit itself never needs to import
    ///   TransportKit's WatchConnectivity-based `TransportKit` product,
    ///   which isn't available on tvOS.
    public init(
        videoURL: URL,
        sampleSource: any WorkoutSampleSource,
        goalEnergy: Double = 400,
        referenceEnergy: Double = 250
    ) {
        self.player = AVPlayer(url: videoURL)
        self.sampleSource = sampleSource
        self.goalEnergy = goalEnergy
        self.referenceEnergy = referenceEnergy
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: player)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()

            VStack(alignment: .trailing, spacing: 12) {
                HeartRateTickerView(heartRate: timeline.latest?.heartRate)
                ActivityRingsOverlayView(
                    currentEnergy: timeline.latest?.activeEnergy ?? 0,
                    goalEnergy: goalEnergy
                )
            }
            .padding()

            VStack {
                Spacer()
                BurnBarView(
                    currentEnergy: timeline.latest?.activeEnergy ?? 0,
                    referenceEnergy: referenceEnergy
                )
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .onAppear {
            timeline.start(source: sampleSource)
            player.play()
        }
        .onDisappear {
            timeline.stop()
            player.pause()
        }
    }
}
