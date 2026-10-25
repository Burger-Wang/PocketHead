// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketHeadCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PocketHeadCore", targets: ["PocketHeadCore"])],
    targets: [
        .target(name: "PocketHeadCore"),
        .testTarget(name: "PocketHeadCoreTests", dependencies: ["PocketHeadCore"])
    ]
)
