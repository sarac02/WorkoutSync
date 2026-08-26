#pragma once

#include <algorithm>
#include <deque>

// Estimates the offset between this device's monotonic clock and a
// counterpart device's, from a series of round-trip timing probes.
//
// Each probe is: send a ping at local time t0, counterpart echoes back its
// own local time t_peer, we receive the echo at local time t2. Assuming a
// roughly symmetric network delay, the counterpart's clock reads t_peer at
// our local time (t0 + t2) / 2, so:
//
//     offset (us - peer) = (t0 + t2) / 2 - t_peer
//
// A single probe is noisy (WatchConnectivity latency is not symmetric, and
// can spike into the hundreds of milliseconds), so we keep a rolling window
// of the last N probes and report the median rather than the mean or the
// latest sample -- median is far less sensitive to the occasional slow probe
// caused by radio contention or the counterpart app being backgrounded.
namespace wt {

class ClockOffsetEstimator {
public:
    explicit ClockOffsetEstimator(size_t windowSize = 9) : windowSize_(windowSize) {}

    void addProbe(double t0, double tPeer, double t2) {
        const double offset = (t0 + t2) / 2.0 - tPeer;
        samples_.push_back(offset);
        if (samples_.size() > windowSize_) {
            samples_.pop_front();
        }
    }

    bool hasEstimate() const { return !samples_.empty(); }

    double medianOffset() const {
        if (samples_.empty()) {
            return 0.0;
        }
        std::deque<double> sorted(samples_);
        std::sort(sorted.begin(), sorted.end());
        return sorted[sorted.size() / 2];
    }

private:
    size_t windowSize_;
    std::deque<double> samples_;
};

} // namespace wt
