// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BookmarkCloud",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BookmarkCloud", targets: ["BookmarkCloud"])],
    targets: [
        .target(name: "BookmarkCloud"),
        .testTarget(name: "BookmarkCloudTests", dependencies: ["BookmarkCloud"])
    ]
)
