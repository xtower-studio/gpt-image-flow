// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageFlowPreflight",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ImageFlowProbe", targets: ["ImageFlowProbe"]),
        .executable(name: "JournalProbe", targets: ["JournalProbe"])
    ],
    targets: [
        .target(name: "PreflightCore"),
        .executableTarget(name: "ImageFlowProbe", resources: [.copy("Fixtures")]),
        .executableTarget(name: "JournalProbe", dependencies: ["PreflightCore"]),
        .testTarget(name: "PreflightCoreTests", dependencies: ["PreflightCore"])
    ]
)
