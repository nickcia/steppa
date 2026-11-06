// swift-tools-version: 6.0
import PackageDescription

// PlanEngine: the rules-based training plan engine.
// Depends only on Foundation so it can be reused in a CLI or on other platforms.
let package = Package(
    name: "PlanEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlanEngine", targets: ["PlanEngine"]),
    ],
    targets: [
        .target(name: "PlanEngine"),
        .testTarget(name: "PlanEngineTests", dependencies: ["PlanEngine"]),
    ]
)
