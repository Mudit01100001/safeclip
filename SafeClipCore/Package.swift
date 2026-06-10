// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SafeClipCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SafeClipCore", targets: ["SafeClipCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "SafeClipCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "SafeClipCoreTests",
            dependencies: ["SafeClipCore"]
        ),
    ]
)
