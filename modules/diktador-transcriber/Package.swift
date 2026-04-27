// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DiktadorTranscriber",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiktadorTranscriber", targets: ["DiktadorTranscriber"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "DiktadorTranscriber",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .testTarget(
            name: "DiktadorTranscriberTests",
            dependencies: ["DiktadorTranscriber"]
        ),
    ]
)
