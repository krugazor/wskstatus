// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "wskstatus",
    platforms: [
        .macOS(.v10_12),
        ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(path: "../TermPlot"),
        .package(name: "swift-argument-parser", url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),

    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "wskstatus",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TermPlot", package: "TermPlot")
            ]),
        .testTarget(
            name: "wskstatusTests",
            dependencies: ["wskstatus"]),
    ]
)
