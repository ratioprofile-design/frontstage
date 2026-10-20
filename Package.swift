// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Frontstage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FrontstageCore", targets: ["FrontstageCore"]),
        .executable(name: "Frontstage", targets: ["FrontstageApp"]),
        .executable(name: "FrontstageWindows", targets: ["FrontstageWindows"])
    ],
    targets: [
        .target(name: "FrontstageCore"),
        .executableTarget(name: "FrontstageApp", dependencies: ["FrontstageCore"]),
        .executableTarget(name: "FrontstageWindows", dependencies: ["FrontstageCore"]),
        .testTarget(name: "FrontstageCoreTests", dependencies: ["FrontstageCore"]),
        .testTarget(name: "FrontstageAppTests", dependencies: ["FrontstageApp"])
    ]
)
