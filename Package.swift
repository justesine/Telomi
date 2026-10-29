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
    targets: [
        .target(
            name: "MemoFlowCore",
            path: "Sources/MemoFlowCore"
        ),
        .executableTarget(
            name: "MemoFlowApp",
            dependencies: ["MemoFlowCore"],
            path: "Sources/MemoFlowApp"
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
            exclude: ["MemoFlowPRDAcceptanceTests.swift", "StabilityTests.swift"],
            sources: ["PRDTestRunner.swift"]
        )
    ]
)
