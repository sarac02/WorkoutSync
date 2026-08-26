// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WorkoutModel",
    // macOS is here purely so this package can be built and unit-tested on
    // any Mac without needing the iOS/watchOS SDKs -- it's the shared
    // sample type/protocol, with zero platform-specific dependencies, so
    // there's no reason to restrict it to the shipping platforms only.
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10), .tvOS(.v17)],
    products: [
        .library(name: "WorkoutModel", targets: ["WorkoutModel"])
    ],
    targets: [
        .target(name: "WorkoutModel", path: "Sources/WorkoutModel"),
        .testTarget(name: "WorkoutModelTests", dependencies: ["WorkoutModel"], path: "Tests/WorkoutModelTests")
    ]
)
