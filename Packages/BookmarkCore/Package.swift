// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BookmarkCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BookmarkCore", targets: ["BookmarkCore"])],
    targets: [
        .target(name: "BookmarkCore"),
        .testTarget(name: "BookmarkCoreTests", dependencies: ["BookmarkCore"])
    ],
    swiftLanguageModes: [.v6]
)
