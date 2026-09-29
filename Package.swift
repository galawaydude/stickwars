// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "STICKTOP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "STICKTOP",
            path: "Sources/STICKTOP",
            swiftSettings: [.unsafeFlags(["-Ounchecked", "-wmo"], .when(configuration: .release))]
        )
    ]
)
