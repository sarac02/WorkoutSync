// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CaptureGuard",
    // Pure Swift/Foundation, no HealthKit dependency at all -- it never
    // touches the actual health record, only the readings a client chooses
    // to transmit/display, so it has no reason to be platform-restricted.
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10), .tvOS(.v17)],
    products: [
        .library(name: "CaptureGuard", targets: ["CaptureGuard"])
    ],
    targets: [
        .target(name: "CaptureGuard", path: "Sources/CaptureGuard"),
        .testTarget(name: "CaptureGuardTests", dependencies: ["CaptureGuard"], path: "Tests/CaptureGuardTests")
    ]
)
