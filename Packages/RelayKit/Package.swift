// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RelayKit",
    // MultipeerConnectivity is available on macOS too, so this whole
    // package -- unlike TransportKit -- can be built and unit-tested here.
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "RelayKit", targets: ["RelayKit"])
    ],
    dependencies: [
        .package(path: "../WorkoutModel"),
        .package(path: "../WireCodec")
    ],
    targets: [
        .target(
            name: "RelayKit",
            dependencies: [
                .product(name: "WorkoutModel", package: "WorkoutModel"),
                .product(name: "WireCodec", package: "WireCodec")
            ],
            path: "Sources/RelayKit"
        ),
        .testTarget(
            name: "RelayKitTests",
            dependencies: [
                "RelayKit",
                .product(name: "WorkoutModel", package: "WorkoutModel")
            ],
            path: "Tests/RelayKitTests"
        )
    ]
)
