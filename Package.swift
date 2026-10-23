// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LookingGlass",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LookingGlass", path: "Sources/LookingGlass")
    ]
)
