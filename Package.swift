// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mobi",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "MobiCore"),
        .executableTarget(
            name: "Mobi",
            dependencies: ["MobiCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MobiCoreTests", dependencies: ["MobiCore"]),
    ]
)
