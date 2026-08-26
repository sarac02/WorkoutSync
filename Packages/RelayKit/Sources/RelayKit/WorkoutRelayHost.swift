import Foundation
import MultipeerConnectivity
import WireCodec
import WorkoutModel

/// Runs on the iPhone. Apple TV has no WatchConnectivity pairing of its own,
/// so this is the "how does Watch data even reach the TV" hop: it
/// rebroadcasts every sample the iPhone receives from the Watch (via
/// `WorkoutTransport`) to whichever Apple TV has joined over the local
/// network.
///
/// Deliberately sends samples with `.unreliable` QoS: like the Watch<->iPhone
/// hop, a dropped live sample should just be skipped, not retransmitted late.
/// Clock-sync pings/echoes use `.reliable`, since a dropped sync probe just
/// means a slightly stale offset estimate rather than a visible glitch.
public final class WorkoutRelayHost: NSObject, @unchecked Sendable {
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private var forwardTask: Task<Void, Never>?

    /// A short code the user confirms on the Apple TV before it's allowed to
    /// join this session -- without this, any nearby device advertising for
    /// the same service type could connect and receive live heart-rate/
    /// calorie data, or inject fake samples as if it were the real Apple TV.
    public let pairingCode: String

    public init(displayName: String) {
        let peerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: RelayServiceType.name)
        pairingCode = String(format: "%04d", Int.random(in: 0...9999))
        super.init()
        session.delegate = self
        advertiser.delegate = self
    }

    /// - Parameter sampleSource: pass `TransportKit.WorkoutTransport.shared`
    ///   from the app layer. RelayKit itself stays off the WatchConnectivity
    ///   product so the same target can also build for tvOS (see
    ///   `WorkoutRelayClient`).
    public func start(sampleSource: any WorkoutSampleSource) {
        advertiser.startAdvertisingPeer()
        forwardTask = Task { [weak self] in
            for await sample in sampleSource.incomingSamples {
                self?.forward(sample)
            }
        }
    }

    public func stop() {
        advertiser.stopAdvertisingPeer()
        forwardTask?.cancel()
        session.disconnect()
    }

    private func forward(_ sample: WorkoutSample) {
        guard !session.connectedPeers.isEmpty else { return }
        guard let data = RelayWireFormat.encodeSample(sample) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }

    private func replyToClockPing(from peerID: MCPeerID) {
        let echo = RelayWireFormat.tagged(.clockEcho, payload: RelayWireFormat.encodeTimestamp(wc_monotonic_time()))
        try? session.send(echo, toPeers: [peerID], with: .reliable)
    }
}

extension WorkoutRelayHost: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {}

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let (tag, _) = RelayWireFormat.untag(data) else { return }
        switch tag {
        case .clockPing:
            replyToClockPing(from: peerID)
        case .sample, .clockEcho:
            break // the host never receives these; only the TV client does
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension WorkoutRelayHost: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        guard let context, let submittedCode = String(data: context, encoding: .utf8), submittedCode == pairingCode else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, session)
    }
}
