// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipHaven",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClipHaven", targets: ["ClipHaven"])],
    targets: [
        .executableTarget(name: "ClipHaven"),
        .testTarget(name: "ClipHavenTests", dependencies: ["ClipHaven"])
    ]
)
