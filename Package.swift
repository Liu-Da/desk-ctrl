// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeskControl",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DeskControl", targets: ["DeskControl"])],
    targets: [
        .target(name: "DeskCore"),
        .executableTarget(name: "DeskControl", dependencies: ["DeskCore"]),
        .testTarget(name: "DeskCoreTests", dependencies: ["DeskCore"])
    ]
)
