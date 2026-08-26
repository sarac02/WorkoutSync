#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One timestamped reading of live workout metrics.
///
/// `timestamp` is expressed in the sender's local `wc_monotonic_time()` clock,
/// not wall time — `WCTransportSession` corrects for the offset between the two
/// devices' clocks before this sample is handed to the overlay renderer.
@interface WTSample : NSObject <NSSecureCoding>

@property (nonatomic, readonly) NSTimeInterval timestamp;
@property (nonatomic, readonly) double heartRate;       // beats per minute
@property (nonatomic, readonly) double activeEnergy;    // kilocalories, cumulative
@property (nonatomic, readonly) double distance;        // meters, cumulative (0 if not applicable)
@property (nonatomic, copy, readonly) NSString *sourceDeviceName;

- (instancetype)initWithTimestamp:(NSTimeInterval)timestamp
                         heartRate:(double)heartRate
                      activeEnergy:(double)activeEnergy
                          distance:(double)distance
                  sourceDeviceName:(NSString *)sourceDeviceName NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Packs the sample into a fixed-size binary payload for low-overhead transport
/// over `WCSession sendMessageData:`. Cheaper to encode/decode and much smaller
/// on the wire than an NSDictionary/NSCoding round trip.
- (NSData *)packedData;
+ (nullable instancetype)unpackFromData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
