// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Budget",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        // Mises à jour automatiques (macOS)
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Budget",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/Budget",
            // Sparkle.framework est copié dans Budget.app/Contents/Frameworks par build-app.sh
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "BudgetTests",
            dependencies: ["Budget"],
            path: "Tests/BudgetTests"
        ),
    ]
)
