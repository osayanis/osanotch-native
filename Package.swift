// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OsaNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Lakr233/SkyLightWindow", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "OsaNotch",
            dependencies: ["SkyLightWindow"],
            path: "Sources/OsaNotch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
