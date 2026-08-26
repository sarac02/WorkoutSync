import CTransport
import WorkoutModel

// Bridging between the pure-Swift `WorkoutSample` (WorkoutModel target,
// safe on every platform) and `WTSample` (CTransport target, Obj-C++,
// WatchConnectivity-only platforms). Kept in this target rather than
// WorkoutModel so WorkoutModel never has to import CTransport.
extension WorkoutSample {
    init(_ wireSample: WTSample) {
        self.init(
            timestamp: wireSample.timestamp,
            heartRate: wireSample.heartRate,
            activeEnergy: wireSample.activeEnergy,
            distance: wireSample.distance,
            sourceDeviceName: wireSample.sourceDeviceName
        )
    }

    var wireSample: WTSample {
        WTSample(timestamp: timestamp, heartRate: heartRate, activeEnergy: activeEnergy, distance: distance, sourceDeviceName: sourceDeviceName)
    }
}
