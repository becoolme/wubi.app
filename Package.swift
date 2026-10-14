// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mobi",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MobiCore"),
        .executableTarget(name: "Mobi", dependencies: ["MobiCore"]),
        .testTarget(name: "MobiCoreTests", dependencies: ["MobiCore"]),
    ]
)
