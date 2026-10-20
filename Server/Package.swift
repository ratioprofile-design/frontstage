// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrontstageServer", platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.110.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3"),
        // Keep the networking dependency graph compatible with the Swift 6.0 toolchain.
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.10.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.81.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", exact: "1.26.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.29.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", exact: "1.34.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", exact: "1.24.0")
    ],
    targets: [
        .executableTarget(name: "FrontstageServer", dependencies: [
            .product(name: "FrontstageCore", package: "frontstage"),
            .product(name: "Vapor", package: "vapor"), .product(name: "Crypto", package: "swift-crypto")
        ])
    ]
)
