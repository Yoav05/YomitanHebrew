// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "YomitanForHebrew",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "YomitanCore",
            targets: ["YomitanCore"]
        ),
        .executable(
            name: "YomitanHebrew",
            targets: ["YomitanHebrew"]
        )
    ],
    targets: [
        .target(
            name: "YomitanCore"
        ),
        .executableTarget(
            name: "YomitanHebrew",
            dependencies: ["YomitanCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "YomitanCoreTests",
            dependencies: ["YomitanCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
