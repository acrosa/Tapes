// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GridKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "GridKit", targets: ["GridKit"])],
    targets: [
        .target(name: "GridKit"),
        .testTarget(name: "GridKitTests", dependencies: ["GridKit"]),
    ]
)
