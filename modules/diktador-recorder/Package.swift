// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DiktadorRecorder",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiktadorRecorder", targets: ["DiktadorRecorder"]),
    ],
    targets: [
        .target(name: "DiktadorRecorder"),
        .testTarget(
            name: "DiktadorRecorderTests",
            dependencies: ["DiktadorRecorder"]
        ),
    ]
)
