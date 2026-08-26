import Foundation
import WorkoutModel

/// Every message on the relay's Multipeer channel is `[1-byte tag][payload]`
/// -- mirrors `TransportKit`'s `WTWireTag` framing for the same reason: one
/// channel needs to carry both live sample data and clock-sync pings/echoes
/// without a second delegate callback path.
enum RelayWireTag: UInt8 {
    case sample = 0x01
    case clockPing = 0x02
    case clockEcho = 0x03
}

/// JSON is deliberately fine for the sample payload, unlike TransportKit's
/// binary wire format: this hop only runs once per phone-to-TV relay session
/// (not per-sample at high frequency the way the raw WatchConnectivity link
/// is used), so the simplicity of Codable outweighs the overhead. The clock
/// ping/echo payloads are a raw 8-byte double, same as CTransport.
enum RelayWireFormat {
    static func tagged(_ tag: RelayWireTag, payload: Data = Data()) -> Data {
        var data = Data([tag.rawValue])
        data.append(payload)
        return data
    }

    /// Splits a raw received message into its tag and payload. `nil` if the
    /// message is empty or the tag byte is unrecognized.
    static func untag(_ data: Data) -> (tag: RelayWireTag, payload: Data)? {
        guard let firstByte = data.first, let tag = RelayWireTag(rawValue: firstByte) else { return nil }
        return (tag, data.dropFirst())
    }

    static func encodeSample(_ sample: WorkoutSample) -> Data? {
        (try? JSONEncoder().encode(sample)).map { tagged(.sample, payload: $0) }
    }

    static func decodeSample(from payload: Data) -> WorkoutSample? {
        try? JSONDecoder().decode(WorkoutSample.self, from: payload)
    }

    static func encodeTimestamp(_ value: Double) -> Data {
        withUnsafeBytes(of: value) { Data($0) }
    }

    static func decodeTimestamp(_ data: Data) -> Double? {
        guard data.count >= MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
    }
}
