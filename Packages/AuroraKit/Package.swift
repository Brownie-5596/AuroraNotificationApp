// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AuroraKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "AuroraKit", targets: ["AuroraKit"]),
        .executable(name: "aurora-watch", targets: ["AuroraWatchCLI"]),
    ],
    targets: [
        .target(name: "AuroraKit"),
        .executableTarget(name: "AuroraWatchCLI", dependencies: ["AuroraKit"]),
        .testTarget(
            name: "AuroraKitTests",
            dependencies: ["AuroraKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
