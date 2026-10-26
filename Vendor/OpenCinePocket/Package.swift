// swift-tools-version: 6.0
import PackageDescription

// Pocket Head uses only the DJI transport and its portable dependencies from
// OpenCine revision 1be846d664da0020ef67f039a34f207c0b047404.
let package = Package(
    name: "OpenCinePocket",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "OpenCineDJI", targets: ["OpenCineDJI"]),
        .library(name: "OpenCineDJIApple", targets: ["OpenCineDJIApple"]),
        .library(name: "OpenCineMotion", targets: ["OpenCineMotion"]),
    ],
    targets: [
        .target(name: "OpenCineCore"),
        .target(name: "OpenCineMedia", dependencies: ["OpenCineCore"]),
        .target(name: "OpenCineMotion", dependencies: ["OpenCineCore"]),
        .target(name: "OpenCineCameraVocabulary", dependencies: [
            "OpenCineCore", "OpenCineMedia", "OpenCineMotion",
        ]),
        .target(name: "OpenCineDJI", dependencies: [
            "OpenCineCore", "OpenCineMedia", "OpenCineMotion", "OpenCineCameraVocabulary",
        ]),
        .target(name: "OpenCineDJIApple", dependencies: [
            "OpenCineCore", "OpenCineDJI", "OpenCineMedia", "OpenCineMotion",
        ]),
    ]
)
