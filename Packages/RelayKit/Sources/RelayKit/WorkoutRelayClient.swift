import Foundation
import MultipeerConnectivity
import WireCodec
import WorkoutModel

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
public final class WorkoutRelayClient: NSObject, WorkoutSampleSource, @unchecked Sendable {
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser
    private let pairingCode: String
    private var continuation: AsyncStream<WorkoutSample>.Continuation?

    private let clockEstimator = wc_clock_estimator_create(9)
    // `sendClockPing` (from the clock-sync Task loop) and `handleClockEcho`
    // (from the MCSessionDelegate callback, a different queue) both touch
    // this -- the same class of race already found and fixed in
    // WorkoutOverlayTimeline and WCClockOffsetEstimator, guarded the same
    // straightforward way here since there's no shared actor to lean on.
    private let pendingPingLock = NSLock()
    private var pendingPingSentAt: Double?
    private var clockSyncTask: Task<Void, Never>?

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
    }

    public func stop() {
        browser.stopBrowsingForPeers()
        clockSyncTask?.cancel()
        session.disconnect()
    }

    private func sendClockPing() {
        guard let hostPeer = session.connectedPeers.first else { return }
        let now = wc_monotonic_time()
        pendingPingLock.lock()
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
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {}

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
