// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OverlayKit",
    // macOS added purely so the interpolation/timeline logic (no UIKit-only
    // APIs) can be unit-tested on any Mac without the iOS SDK.
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "OverlayKit", targets: ["OverlayKit"])
    ],
    dependencies: [
        .package(path: "../WorkoutModel"),
        .package(path: "../WireCodec")
    ],
    targets: [
        .target(
            name: "OverlayKit",
            dependencies: [
                .product(name: "WorkoutModel", package: "WorkoutModel"),
                .product(name: "WireCodec", package: "WireCodec")
            ],
            path: "Sources/OverlayKit"
        ),
        .testTarget(
            name: "OverlayKitTests",
            dependencies: [
                "OverlayKit",
                .product(name: "WorkoutModel", package: "WorkoutModel")
            ],
            path: "Tests/OverlayKitTests"
        )
    ]
)
