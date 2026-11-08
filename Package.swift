// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dyland",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Dyland", path: "Sources")],
    swiftLanguageModes: [.v5]
)
