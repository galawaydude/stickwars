// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "STICKWARS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "STICKWARS",
            path: "Sources/STICKWARS",
            swiftSettings: [.unsafeFlags(["-Ounchecked", "-wmo"], .when(configuration: .release))]
        )
    ]
)
