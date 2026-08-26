#import <Foundation/Foundation.h>
#import "WTSample.h"

NS_ASSUME_NONNULL_BEGIN

/// Low-level Watch \<-\> iPhone transport built on WatchConnectivity.
///
/// This is the piece the app layer should never need to think about: picking
/// the right WCSession API for the moment (interactive `sendMessage:` while
/// reachable, `updateApplicationContext:` as a fallback when the counterpart
/// app isn't foreground/reachable), and correcting for the fact that the
/// Watch's and phone's clocks are not the same clock. Samples handed out via
/// the handler have already been re-timestamped into the *receiver's* local
/// clock so the overlay renderer can compare them directly against
/// `wc_monotonic_time()` / the video player's timeline without drift.
@interface WCTransportSession : NSObject

+ (instancetype)shared;

/// Activates the underlying WCSession and begins listening. Safe to call
/// more than once. `sampleHandler` is invoked on an arbitrary background
/// queue whenever a sample arrives from the counterpart device.
- (void)activateWithSampleHandler:(void (^)(WTSample *sample))sampleHandler;

/// Sends a live sample to the counterpart device, choosing the lowest-latency
/// transport available right now. Best-effort: an unreachable counterpart
/// silently drops interactive sends rather than queuing them, since a stale
/// heart-rate reading delivered late is worse than a gap in the overlay.
- (void)sendSample:(WTSample *)sample;

/// Current best estimate of (this device's clock) − (counterpart's clock),
/// in seconds, derived from a rolling set of round-trip timing probes.
/// Returns 0 before the first estimate is available.
@property (nonatomic, readonly) NSTimeInterval estimatedClockOffsetToCounterpart;

@end

NS_ASSUME_NONNULL_END
