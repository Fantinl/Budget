// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Budget",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14), .iOS(.v17)],
    targets: [
        .executableTarget(name: "Budget", path: "Sources/Budget")
    ]
)
