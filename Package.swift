// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OsaNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OsaNotch",
            path: "Sources/OsaNotch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
