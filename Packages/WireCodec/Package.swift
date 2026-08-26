// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WireCodec",
    // Pure C++ under a C-callable API, no Apple frameworks at all -- so
    // unlike CTransport (which needs WatchConnectivity, iOS/watchOS only),
    // this half of the wire protocol can be built and unit-tested on any
    // Mac, which is exactly why it was split out of CTransport.
    platforms: [.macOS(.v13), .iOS(.v17), .watchOS(.v10), .tvOS(.v17)],
    products: [
        .library(name: "WireCodec", targets: ["WireCodec"])
    ],
    targets: [
        .target(name: "WireCodec", path: "Sources/WireCodec", publicHeadersPath: "include"),
        .testTarget(name: "WireCodecTests", dependencies: ["WireCodec"], path: "Tests/WireCodecTests")
    ]
)
