// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemoFlow",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MemoFlowCore",
            targets: ["MemoFlowCore"]
        ),
        .executable(
            name: "MemoFlowApp",
            targets: ["MemoFlowApp"]
        )
    ],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.6.1")],
    targets: [
        .target(
            name: "MemoFlowCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/MemoFlowCore"
        ),
        .executableTarget(
            name: "MemoFlowApp",
            dependencies: ["MemoFlowCore"],
            path: "Sources/MemoFlowApp",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "MemoFlowCoreTests",
            dependencies: ["MemoFlowCore"],
            path: "Tests/MemoFlowCoreTests",
            exclude: ["PRDTestRunner.swift"]
        ),
        .executableTarget(
            name: "MemoFlowAcceptanceRunner",
            dependencies: ["MemoFlowCore"],
            path: "Tests/MemoFlowCoreTests",
            exclude: ["MemoFlowPRDAcceptanceTests.swift", "StabilityTests.swift", "ObsidianPhasedTests.swift", "LiveStreamingTests.swift"],
            sources: ["PRDTestRunner.swift"]
        )
    ]
)
