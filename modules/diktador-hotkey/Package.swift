// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DiktadorHotkey",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiktadorHotkey", targets: ["DiktadorHotkey"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "DiktadorHotkey",
            dependencies: [
                .product(name: "HotKey", package: "HotKey"),
            ]
        ),
        .testTarget(
            name: "DiktadorHotkeyTests",
            dependencies: ["DiktadorHotkey"]
        ),
    ]
)
