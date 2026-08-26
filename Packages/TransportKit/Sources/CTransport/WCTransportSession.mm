#import "include/WCTransportSession.h"
#import <WatchConnectivity/WatchConnectivity.h>
#import <WireCodec.h>

// Wire framing: every payload we send is [1-byte tag][payload]. This lets one
// WCSession channel carry both real sample data and clock-sync pings without
// a second delegate callback path.
typedef NS_ENUM(uint8_t, WTWireTag) {
    WTWireTagSample = 0x01,
    WTWireTagClockPing = 0x02,
};

@interface WCTransportSession () <WCSessionDelegate>
@property (nonatomic, copy) void (^sampleHandler)(WTSample *sample);
@property (nonatomic, strong) NSTimer *clockSyncTimer;
@end

@implementation WCTransportSession {
    WCClockOffsetEstimator *_clockOffsetEstimator;
}

+ (instancetype)shared {
    static WCTransportSession *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WCTransportSession alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _clockOffsetEstimator = wc_clock_estimator_create(9);
    }
    return self;
}

- (void)dealloc {
    wc_clock_estimator_destroy(_clockOffsetEstimator);
}

- (void)activateWithSampleHandler:(void (^)(WTSample *sample))sampleHandler {
    self.sampleHandler = sampleHandler;

    if (![WCSession isSupported]) {
        return; // e.g. running on a device/platform without a counterpart pairing
    }

    WCSession *session = WCSession.defaultSession;
    session.delegate = self;
    [session activateSession];

    // Probe the clock offset periodically for the life of the session. A
    // fixed 4s cadence is a compromise: frequent enough that the estimate
    // tracks clock drift over a 30-60 minute workout, infrequent enough that
    // it doesn't compete for airtime with the actual sample stream.
    self.clockSyncTimer = [NSTimer scheduledTimerWithTimeInterval:4.0
                                                            target:self
                                                          selector:@selector(sendClockSyncPing)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)sendSample:(WTSample *)sample {
    WCSession *session = WCSession.defaultSession;
    if (!WCSession.isSupported || session.activationState != WCSessionActivationStateActivated) {
        return;
    }
    if (!session.isReachable) {
        // A stale heart-rate reading delivered a few seconds late is more
        // misleading on screen than a brief gap in the overlay -- so unlike
        // WorkoutKit's scheduled compositions, live samples are dropped
        // rather than queued via updateApplicationContext when unreachable.
        return;
    }

    NSData *tagged = [self dataByTagging:WTWireTagSample payload:sample.packedData];
    [session sendMessageData:tagged replyHandler:nil errorHandler:nil];
}

- (NSTimeInterval)estimatedClockOffsetToCounterpart {
    return wc_clock_estimator_has_estimate(_clockOffsetEstimator) ? wc_clock_estimator_median_offset(_clockOffsetEstimator) : 0.0;
}

#pragma mark - Clock sync

- (void)sendClockSyncPing {
    WCSession *session = WCSession.defaultSession;
    if (session.activationState != WCSessionActivationStateActivated || !session.isReachable) {
        return;
    }

    NSTimeInterval t0 = wc_monotonic_time();
    NSData *pingPayload = [NSData dataWithBytes:&t0 length:sizeof(t0)];
    NSData *tagged = [self dataByTagging:WTWireTagClockPing payload:pingPayload];

    __weak typeof(self) weakSelf = self;
    [session sendMessageData:tagged
                 replyHandler:^(NSData * _Nonnull replyData) {
        NSTimeInterval t2 = wc_monotonic_time();
        if (replyData.length < sizeof(NSTimeInterval)) return;
        NSTimeInterval tPeer;
        memcpy(&tPeer, replyData.bytes, sizeof(tPeer));
        [weakSelf recordRoundTripWithT0:t0 tPeer:tPeer t2:t2];
    }
                 errorHandler:nil];
}

- (void)recordRoundTripWithT0:(NSTimeInterval)t0 tPeer:(NSTimeInterval)tPeer t2:(NSTimeInterval)t2 {
    wc_clock_estimator_add_probe(_clockOffsetEstimator, t0, tPeer, t2);
}

#pragma mark - Framing helpers

- (NSData *)dataByTagging:(WTWireTag)tag payload:(NSData *)payload {
    NSMutableData *tagged = [NSMutableData dataWithBytes:&tag length:sizeof(tag)];
    [tagged appendData:payload];
    return tagged;
}

#pragma mark - WCSessionDelegate

- (void)session:(WCSession *)session activationDidCompleteWithState:(WCSessionActivationState)activationState error:(NSError *)error {
    // No-op: sendSample/sendClockSyncPing already guard on activationState.
}

- (void)session:(WCSession *)session didReceiveMessageData:(NSData *)messageData replyHandler:(void (^)(NSData * _Nonnull))replyHandler {
    if (messageData.length < 1) return;
    WTWireTag tag;
    memcpy(&tag, messageData.bytes, sizeof(tag));
    NSData *payload = [messageData subdataWithRange:NSMakeRange(1, messageData.length - 1)];

    switch (tag) {
        case WTWireTagClockPing: {
            // Echo our current local time straight back so the sender can
            // complete its round-trip offset calculation.
            NSTimeInterval now = wc_monotonic_time();
            replyHandler([NSData dataWithBytes:&now length:sizeof(now)]);
            break;
        }
        case WTWireTagSample: {
            [self handleIncomingSamplePayload:payload];
            replyHandler([NSData data]);
            break;
        }
    }
}

- (void)session:(WCSession *)session didReceiveMessageData:(NSData *)messageData {
    if (messageData.length < 1) return;
    WTWireTag tag;
    memcpy(&tag, messageData.bytes, sizeof(tag));
    if (tag != WTWireTagSample) return;
    NSData *payload = [messageData subdataWithRange:NSMakeRange(1, messageData.length - 1)];
    [self handleIncomingSamplePayload:payload];
}

- (void)handleIncomingSamplePayload:(NSData *)payload {
    WTSample *sample = [WTSample unpackFromData:payload];
    if (!sample) return;

    // Re-timestamp into our local clock before handing it to the app layer,
    // so overlay code can compare it directly to wc_monotonic_time()/the
    // video player's timeline without knowing anything about WatchConnectivity.
    NSTimeInterval correctedTimestamp = sample.timestamp + self.estimatedClockOffsetToCounterpart;
    WTSample *corrected = [[WTSample alloc] initWithTimestamp:correctedTimestamp
                                                      heartRate:sample.heartRate
                                                   activeEnergy:sample.activeEnergy
                                                       distance:sample.distance
                                               sourceDeviceName:sample.sourceDeviceName];
    if (self.sampleHandler) {
        self.sampleHandler(corrected);
    }
}

#if TARGET_OS_IOS
- (void)sessionDidBecomeInactive:(WCSession *)session {}
- (void)sessionDidDeactivate:(WCSession *)session {
    [session activateSession];
}
#endif

@end
