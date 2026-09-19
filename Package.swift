// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "ImageFlow", platforms: [.macOS(.v14)], products: [
    .executable(name: "ImageFlow", targets: ["ImageFlow"])
], targets: [
    .target(name: "FlowCore"),
    .executableTarget(name: "ImageFlow", dependencies: ["FlowCore"], resources: [.copy("Resources")]),
    .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"])
])
