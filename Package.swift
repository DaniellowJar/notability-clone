// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotabilityCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotabilityCore", targets: ["NotabilityCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.28.0")
    ],
    targets: [
        .target(
            name: "NotabilityCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "NotabilityCoreTests",
            dependencies: ["NotabilityCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)