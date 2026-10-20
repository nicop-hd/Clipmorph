// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Clipmorph",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Clipmorph", path: "Sources/Clipmorph")
    ]
)
