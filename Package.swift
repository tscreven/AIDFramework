// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OrefSwiftCLI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "oref-swift", targets: ["OrefSwiftCLI"]),
        .library(name: "OrefSwiftModels", targets: ["OrefSwiftModels"]),
        .library(name: "OrefSwiftAlgorithm", targets: ["OrefSwiftAlgorithm"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "OrefSwiftModels",
            dependencies: []
        ),
        .target(
            name: "OrefSwiftAlgorithm",
            dependencies: ["OrefSwiftModels"]
        ),
        .executableTarget(
            name: "OrefSwiftCLI",
            dependencies: [
                "OrefSwiftModels",
                "OrefSwiftAlgorithm",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "OrefSwiftCLITests",
            dependencies: [
                "OrefSwiftCLI",
                "OrefSwiftModels",
                "OrefSwiftAlgorithm"
            ]
        )
    ]
)
