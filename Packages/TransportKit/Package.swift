// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TransportKit",
    platforms: [.iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "TransportKit", targets: ["TransportKit"])
    ],
    dependencies: [
        .package(path: "../WorkoutModel"),
        .package(path: "../WireCodec")
    ],
    targets: [
        .target(
            name: "CTransport",
            dependencies: [.product(name: "WireCodec", package: "WireCodec")],
            path: "Sources/CTransport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("WatchConnectivity")
            ]
        ),
        .target(
            name: "TransportKit",
            dependencies: [
                "CTransport",
                .product(name: "WorkoutModel", package: "WorkoutModel"),
                .product(name: "WireCodec", package: "WireCodec")
            ],
            path: "Sources/TransportKit"
        ),
        .testTarget(
            name: "TransportKitTests",
            dependencies: ["TransportKit"],
            path: "Tests/TransportKitTests"
        )
    ]
)
