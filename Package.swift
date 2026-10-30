// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Voca",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Voca", path: "Sources/Voca", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
