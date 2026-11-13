// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GlassDock",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlassDockMediaRemote", type: .dynamic, targets: ["GlassDockMediaRemote"])
    ],
    targets: [
        .executableTarget(name: "GlassDock", path: "Sources/GlassDock"),
        .target(name: "GlassDockMediaRemote", path: "Sources/GlassDockMediaRemote")
    ]
)
