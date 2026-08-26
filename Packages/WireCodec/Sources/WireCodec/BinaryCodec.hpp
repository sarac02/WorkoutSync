#pragma once

#include "include/WireCodec.h"
#include <cstring>

// Trivial memcpy-based pack/unpack for WCSampleWire. Kept as plain C++ (no
// Foundation) so it's easy to reason about byte for byte -- this is the
// "low level" part of the transport: a dictionary or NSCoding round trip is
// fine for correctness but costs orders of magnitude more CPU and bytes-on-
// the-wire than a fixed-size struct, which matters when sending several
// samples a second over WatchConnectivity for the lifetime of a workout.
namespace wt {

inline void encode(const WCSampleWire &sample, uint8_t *outBuffer) {
    std::memcpy(outBuffer, &sample, sizeof(WCSampleWire));
}

inline bool decode(const uint8_t *inBuffer, size_t length, WCSampleWire *outSample) {
    if (length < sizeof(WCSampleWire)) {
        return false;
    }
    std::memcpy(outSample, inBuffer, sizeof(WCSampleWire));
    outSample->sourceDeviceName[sizeof(outSample->sourceDeviceName) - 1] = '\0';
    return true;
}

} // namespace wt
