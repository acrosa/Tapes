// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapeEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "TapeEngine", targets: ["TapeEngine"])],
    targets: [
        .target(name: "TapeEngine"),
        .testTarget(name: "TapeEngineTests", dependencies: ["TapeEngine"]),
    ]
)
