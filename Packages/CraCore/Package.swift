// swift-tools-version:5.10
import PackageDescription

// Cra's decisions that need no window and no Chromium: models, Arc import mapping, layout
// arithmetic. A package of its own so `swift test --package-path Packages/CraCore` builds
// and runs without vendor/cef (a target in the root package would build CEF first).
let package = Package(
    name: "CraCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CraCore", targets: ["CraCore"]),
    ],
    targets: [
        .target(name: "CraCore"),
        .testTarget(name: "CraCoreTests", dependencies: ["CraCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageVersions: [.v5]
)
