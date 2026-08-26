import WireCodec

/// The one clock everything in this app compares timestamps against:
/// `WCTransportSession` stamps outgoing samples with it, corrects incoming
/// ones into the receiver's own reading of it, and `OverlayKit`'s
/// `WorkoutOverlayTimeline` calls it to ask "what time is it now" when
/// deciding what to render. Backed by `CLOCK_MONOTONIC` (see WireCodec)
/// rather than `CACurrentMediaTime()` because the latter is unavailable on
/// watchOS -- using one shared clock function everywhere also means the
/// Watch and iPhone sides of the transport are provably comparing apples to
/// apples, instead of two different "monotonic" clocks that happen to
/// usually agree.
public func workoutSyncMonotonicTime() -> Double {
    wc_monotonic_time()
}
