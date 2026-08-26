#include "include/WireCodec.h"
#include "BinaryCodec.hpp"
#include "ClockOffsetEstimator.hpp"
#include <mutex>
#include <time.h>

double wc_monotonic_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

size_t wc_wire_sample_size(void) {
    return sizeof(WCSampleWire);
}

void wc_encode_sample(const WCSampleWire *sample, uint8_t *outBuffer) {
    wt::encode(*sample, outBuffer);
}

int wc_decode_sample(const uint8_t *inBuffer, size_t length, WCSampleWire *outSample) {
    return wt::decode(inBuffer, length, outSample) ? 1 : 0;
}

// `WCTransportSession` writes a new probe from whatever queue
// WatchConnectivity happens to deliver its reply-handler callback on, while
// `WorkoutTransport.estimatedClockOffset` is a public property that can be
// read from any thread the app calls it from (e.g. the main thread, for a
// debug overlay) -- two genuinely different threads touching the same
// `std::deque` with no synchronization otherwise. A single mutex per
// estimator is cheap enough that there's no reason to skip it.
struct WCClockOffsetEstimator {
    wt::ClockOffsetEstimator impl;
    mutable std::mutex mutex;
    explicit WCClockOffsetEstimator(size_t windowSize) : impl(windowSize) {}
};

WCClockOffsetEstimator *wc_clock_estimator_create(size_t windowSize) {
    return new WCClockOffsetEstimator(windowSize);
}

void wc_clock_estimator_destroy(WCClockOffsetEstimator *estimator) {
    delete estimator;
}

void wc_clock_estimator_add_probe(WCClockOffsetEstimator *estimator, double t0, double tPeer, double t2) {
    std::lock_guard<std::mutex> lock(estimator->mutex);
    estimator->impl.addProbe(t0, tPeer, t2);
}

int wc_clock_estimator_has_estimate(const WCClockOffsetEstimator *estimator) {
    std::lock_guard<std::mutex> lock(estimator->mutex);
    return estimator->impl.hasEstimate() ? 1 : 0;
}

double wc_clock_estimator_median_offset(const WCClockOffsetEstimator *estimator) {
    std::lock_guard<std::mutex> lock(estimator->mutex);
    return estimator->impl.medianOffset();
}
