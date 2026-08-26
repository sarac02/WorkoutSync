import Foundation
import MultipeerConnectivity
import Observation
import WireCodec
import WorkoutModel

/// Surfaced to the app layer so a wrong pairing code or a connection that
/// never completes is visible and recoverable, instead of the TV silently
/// sitting on a screen that looks like it's waiting for data that will
/// never arrive.
public enum RelayConnectionState: Sendable, Equatable {
    case connecting
    case connected
    case failed
}

/// Runs on Apple TV. Joins the iPhone's relay session and exposes what it
/// receives as a `WorkoutSampleSource`, so `OverlayKit.WorkoutOverlayTimeline`
/// can drive the TV's overlay exactly the way it drives the iPhone's --
/// the overlay code has no idea whether its samples came over
/// WatchConnectivity or got relayed twice.
///
/// Runs its own round-trip clock-sync against the host over this Multipeer
/// link (mirroring `TransportKit`'s WatchConnectivity clock sync) rather
/// than assuming the iPhone's clock and this Apple TV's clock agree --
/// they're two independent devices, same as Watch and iPhone are.
@Observable
public final class WorkoutRelayClient: NSObject, WorkoutSampleSource, @unchecked Sendable {
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser
    private let pairingCode: String
    private var continuation: AsyncStream<WorkoutSample>.Continuation?

    public private(set) var connectionState: RelayConnectionState = .connecting
    private var connectTimeoutTask: Task<Void, Never>?

    private let clockEstimator = wc_clock_estimator_create(9)
    // `sendClockPing` (from the clock-sync Task loop) and `handleClockEcho`
    // (from the MCSessionDelegate callback, a different queue) both touch
    // this -- the same class of race already found and fixed in
    // WorkoutOverlayTimeline and WCClockOffsetEstimator, guarded the same
    // straightforward way here since there's no shared actor to lean on.
    private let pendingPingLock = NSLock()
    private var pendingPingSentAt: Double?
    private var clockSyncTask: Task<Void, Never>?

    @ObservationIgnored
    public lazy var incomingSamples: AsyncStream<WorkoutSample> = {
        AsyncStream { self.continuation = $0 }
    }()

    /// - Parameter pairingCode: the code displayed on the iPhone (see
    ///   `WorkoutRelayHost.pairingCode`) -- required so this Apple TV can't
    ///   join just any nearby "workoutsync" advertiser.
    public init(displayName: String, pairingCode: String) {
        let peerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: RelayServiceType.name)
        self.pairingCode = pairingCode
        super.init()
        session.delegate = self
        browser.delegate = self
    }

    deinit {
        wc_clock_estimator_destroy(clockEstimator)
    }

    public func start() {
        connectionState = .connecting
        browser.startBrowsingForPeers()
        // A fixed 4s cadence, same reasoning as WCTransportSession's Watch
        // <-> iPhone sync timer: frequent enough to track drift over a long
        // workout, infrequent enough not to compete with the sample stream.
        clockSyncTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.sendClockPing()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        // Without this, a wrong pairing code (host silently declines) or a
        // host that's simply unreachable leaves this stuck on "connecting"
        // forever, with no way for the app layer to know to offer a retry.
        connectTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.connectionState == .connecting {
                self.connectionState = .failed
            }
        }
    }

    public func stop() {
        browser.stopBrowsingForPeers()
        clockSyncTask?.cancel()
        connectTimeoutTask?.cancel()
        session.disconnect()
    }

    private func sendClockPing() {
        guard let hostPeer = session.connectedPeers.first else { return }
        let now = wc_monotonic_time()

        // Unlike WCSession's sendMessage, MCSession's send has no built-in
        // reply-handler correlation, so a single shared "pending ping"
        // variable is all that ties an echo back to the ping it answers.
        // Without this guard, sending a new ping before the previous one's
        // echo arrives would pair that echo with the wrong ping's
        // timestamp. The 8s cutoff (2x the ping interval) self-heals if an
        // echo is simply lost, instead of permanently blocking future syncs.
        pendingPingLock.lock()
        if let pending = pendingPingSentAt, now - pending < 8.0 {
            pendingPingLock.unlock()
            return
        }
        pendingPingSentAt = now
        pendingPingLock.unlock()

        let ping = RelayWireFormat.tagged(.clockPing)
        try? session.send(ping, toPeers: [hostPeer], with: .reliable)
    }

    private func handleClockEcho(_ payload: Data) {
        let t2 = wc_monotonic_time()
        pendingPingLock.lock()
        let t0 = pendingPingSentAt
        pendingPingSentAt = nil
        pendingPingLock.unlock()
        guard let t0, let tPeer = RelayWireFormat.decodeTimestamp(payload) else { return }
        wc_clock_estimator_add_probe(clockEstimator, t0, tPeer, t2)
    }

    private func handleIncomingSample(_ payload: Data) {
        guard let relayed = RelayWireFormat.decodeSample(from: payload) else { return }

        let corrected: WorkoutSample
        if wc_clock_estimator_has_estimate(clockEstimator) == 1 {
            // Same correction WCTransportSession applies for Watch<->iPhone:
            // re-timestamp into this device's own clock using the measured
            // offset, rather than either trusting the iPhone's clock
            // directly or discarding the timestamp's precision entirely.
            let offset = wc_clock_estimator_median_offset(clockEstimator)
            corrected = WorkoutSample(
                timestamp: relayed.timestamp + offset,
                heartRate: relayed.heartRate,
                activeEnergy: relayed.activeEnergy,
                distance: relayed.distance,
                sourceDeviceName: relayed.sourceDeviceName
            )
        } else {
            // No clock-sync estimate yet (e.g. just connected) -- fall back
            // to stamping with local receipt time rather than using an
            // uncorrected iPhone-clock timestamp against this device's clock.
            corrected = WorkoutSample(
                timestamp: wc_monotonic_time(),
                heartRate: relayed.heartRate,
                activeEnergy: relayed.activeEnergy,
                distance: relayed.distance,
                sourceDeviceName: relayed.sourceDeviceName
            )
        }
        continuation?.yield(corrected)
    }
}

extension WorkoutRelayClient: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // MultipeerConnectivity can call this on an arbitrary queue; hop to
        // the main actor before touching `connectionState`; the app layer
        // observes it from SwiftUI.
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectionState = .connected
                self.connectTimeoutTask?.cancel()
            case .notConnected:
                // A drop after having connected is as much a failure as
                // never connecting in the first place -- either way the
                // app layer needs a chance to offer a retry.
                if self.connectionState != .failed {
                    self.connectionState = .failed
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let (tag, payload) = RelayWireFormat.untag(data) else { return }
        switch tag {
        case .sample:
            handleIncomingSample(payload)
        case .clockEcho:
            handleClockEcho(payload)
        case .clockPing:
            break // only the host replies to pings; the client never receives one
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension WorkoutRelayClient: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let context = pairingCode.data(using: .utf8)
        browser.invitePeer(peerID, to: session, withContext: context, timeout: 10)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
