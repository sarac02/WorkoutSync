#import "include/WTSample.h"
#import <WireCodec.h>

@implementation WTSample

- (instancetype)initWithTimestamp:(NSTimeInterval)timestamp
                         heartRate:(double)heartRate
                      activeEnergy:(double)activeEnergy
                          distance:(double)distance
                  sourceDeviceName:(NSString *)sourceDeviceName {
    if ((self = [super init])) {
        _timestamp = timestamp;
        _heartRate = heartRate;
        _activeEnergy = activeEnergy;
        _distance = distance;
        _sourceDeviceName = [sourceDeviceName copy];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSTimeInterval timestamp = [coder decodeDoubleForKey:@"timestamp"];
    double heartRate = [coder decodeDoubleForKey:@"heartRate"];
    double activeEnergy = [coder decodeDoubleForKey:@"activeEnergy"];
    double distance = [coder decodeDoubleForKey:@"distance"];
    NSString *sourceDeviceName = [coder decodeObjectOfClass:[NSString class] forKey:@"sourceDeviceName"] ?: @"";
    return [self initWithTimestamp:timestamp
                          heartRate:heartRate
                       activeEnergy:activeEnergy
                           distance:distance
                   sourceDeviceName:sourceDeviceName];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeDouble:self.timestamp forKey:@"timestamp"];
    [coder encodeDouble:self.heartRate forKey:@"heartRate"];
    [coder encodeDouble:self.activeEnergy forKey:@"activeEnergy"];
    [coder encodeDouble:self.distance forKey:@"distance"];
    [coder encodeObject:self.sourceDeviceName forKey:@"sourceDeviceName"];
}

- (NSData *)packedData {
    WCSampleWire wire = {0};
    wire.timestamp = self.timestamp;
    wire.heartRate = self.heartRate;
    wire.activeEnergy = self.activeEnergy;
    wire.distance = self.distance;

    const char *utf8Name = self.sourceDeviceName.UTF8String ?: "";
    strncpy(wire.sourceDeviceName, utf8Name, sizeof(wire.sourceDeviceName) - 1);

    NSMutableData *data = [NSMutableData dataWithLength:wc_wire_sample_size()];
    wc_encode_sample(&wire, (uint8_t *)data.mutableBytes);
    return data;
}

+ (nullable instancetype)unpackFromData:(NSData *)data {
    WCSampleWire wire = {0};
    if (!wc_decode_sample((const uint8_t *)data.bytes, data.length, &wire)) {
        return nil;
    }
    NSString *sourceDeviceName = [NSString stringWithUTF8String:wire.sourceDeviceName] ?: @"";
    return [[WTSample alloc] initWithTimestamp:wire.timestamp
                                      heartRate:wire.heartRate
                                   activeEnergy:wire.activeEnergy
                                       distance:wire.distance
                               sourceDeviceName:sourceDeviceName];
}

@end
