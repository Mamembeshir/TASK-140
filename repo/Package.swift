// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForgeFlow",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ForgeFlow", targets: ["ForgeFlow"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    ],
    targets: [
        .target(
            name: "ForgeFlow",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "ForgeFlow"
        ),
        .testTarget(
            name: "ForgeFlowTests",
            dependencies: ["ForgeFlow"],
            path: "ForgeFlowTests"
        ),
    ]
)
