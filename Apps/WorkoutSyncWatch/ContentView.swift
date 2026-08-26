import SwiftUI

struct ContentView: View {
    @State private var manager = WorkoutSessionManager()
    @State private var authError: String?

    var body: some View {
        VStack(spacing: 12) {
            Text(manager.isRunning ? "Streaming to iPhone" : "Not started")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if manager.isHeartRateSignalStale && manager.isRunning {
                Text("Checking heart rate…")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            } else {
                Text("\(Int(manager.currentHeartRate)) BPM")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            Text("\(Int(manager.currentActiveEnergy)) kcal")
                .font(.headline)

            if let reason = manager.lastRejectedHeartRateReason {
                Text("Ignored a reading: \(reason)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button(manager.isRunning ? "End Workout" : "Start Workout") {
                toggleWorkout()
            }
            .tint(manager.isRunning ? .red : .green)

            if let authError {
                Text(authError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if let sessionError = manager.sessionError {
                Text("Session failed: \(sessionError)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Text("Live workout sessions often fail in the Simulator — try a real Apple Watch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func toggleWorkout() {
        if manager.isRunning {
            manager.stop()
            return
        }
        Task {
            do {
                try await manager.requestAuthorization()
                try manager.start()
            } catch {
                authError = error.localizedDescription
            }
        }
    }
}
