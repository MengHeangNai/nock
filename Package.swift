// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GlassDock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GlassDock", path: "Sources/GlassDock")
    ]
)
