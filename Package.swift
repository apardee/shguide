// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "shguide",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .executable(name: "shguide", targets: ["shguide"]),
        .executable(name: "shguide-eval", targets: ["ShguideEval"]),
        .library(name: "ShguideCore", targets: ["ShguideCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "shguide",
            dependencies: [
                "ShguideCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "ShguideCore"
        ),
        .executableTarget(
            name: "ShguideEval",
            dependencies: [
                "ShguideCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ShguideCoreTests",
            dependencies: ["ShguideCore"]
        ),
    ]
)
