#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// C-callable mirror of one workout sample, laid out identically to the
/// bytes sent over the wire. Kept plain-C so both the Obj-C++ transport
/// layer (CTransport, iOS/watchOS) and Swift test code on any platform can
/// call into the same encode/decode/clock-sync logic without needing
/// Foundation or WatchConnectivity.
typedef struct {
    double timestamp;
    double heartRate;
    double activeEnergy;
    double distance;
    char sourceDeviceName[32]; // NUL-terminated, truncated if longer
} WCSampleWire;

/// Size in bytes of the encoded wire format. `outBuffer`/`inBuffer` passed
/// to encode/decode below must be at least this many bytes.
size_t wc_wire_sample_size(void);

/// Packs `sample` into `outBuffer` (must be >= wc_wire_sample_size() bytes).
void wc_encode_sample(const WCSampleWire *sample, uint8_t *outBuffer);

/// Unpacks a sample from `inBuffer`/`length`. Returns 1 on success, 0 if
/// `length` is too small to contain a full sample.
int wc_decode_sample(const uint8_t *inBuffer, size_t length, WCSampleWire *outSample);

/// Opaque handle to a rolling clock-offset estimator. See
/// ClockOffsetEstimator.hpp for the math and its reasoning.
typedef struct WCClockOffsetEstimator WCClockOffsetEstimator;

WCClockOffsetEstimator *wc_clock_estimator_create(size_t windowSize);
void wc_clock_estimator_destroy(WCClockOffsetEstimator *estimator);

/// Records one round-trip probe: `t0` (we sent a ping), `tPeer` (the
/// counterpart's clock when it received/echoed it), `t2` (we received the
/// echo).
void wc_clock_estimator_add_probe(WCClockOffsetEstimator *estimator, double t0, double tPeer, double t2);

int wc_clock_estimator_has_estimate(const WCClockOffsetEstimator *estimator);
double wc_clock_estimator_median_offset(const WCClockOffsetEstimator *estimator);

/// Monotonic clock in seconds, backed by CLOCK_MONOTONIC. Used instead of
/// `CACurrentMediaTime()` because QuartzCore's clock is unavailable on
/// watchOS, and the transport needs the exact same clock source on both
/// ends of the Watch <-> iPhone link for the offset math to mean anything.
double wc_monotonic_time(void);

#ifdef __cplusplus
}
#endif
