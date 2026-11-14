// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Telomi",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TelomiCore",
            targets: ["TelomiCore"]
        ),
        .executable(
            name: "TelomiApp",
            targets: ["TelomiApp"]
        )
    ],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.6.1")],
    targets: [
        .target(
            name: "TelomiCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/TelomiCore"
        ),
        .executableTarget(
            name: "TelomiApp",
            dependencies: ["TelomiCore"],
            path: "Sources/TelomiApp",
            exclude: ["LaunchScreen.storyboard"],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "TelomiCoreTests",
            dependencies: ["TelomiCore"],
            path: "Tests/TelomiCoreTests",
            exclude: ["PRDTestRunner.swift"]
        ),
        .executableTarget(
            name: "TelomiAcceptanceRunner",
            dependencies: ["TelomiCore"],
            path: "Tests/TelomiCoreTests",
            exclude: ["TelomiPRDAcceptanceTests.swift", "StabilityTests.swift", "ObsidianPhasedTests.swift", "LiveStreamingTests.swift", "V14IncrementalTests.swift"],
            sources: ["PRDTestRunner.swift"]
        )
    ]
)
