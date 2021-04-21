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
        .package(name: "TermPlot", url: "https://github.com/krugazor/TermPlot", from: "1.2.2"),
        .package(name: "swift-argument-parser", url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
        .package(name: "AnyCodable", url: "https://github.com/Flight-School/AnyCodable", from: "0.4.0"),
        .package(name: "Kitura", url: "https://github.com/Kitura/Kitura", from: "2.9.1"),
        .package(name: "KituraStencil", url: "https://github.com/Kitura/Kitura-StencilTemplateEngine", from: "1.11.1"),
        .package(name: "MarkdownKit", url:"https://github.com/objecthub/swift-markdownkit", from:"1.0.5")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "wskstatus",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TermPlot", package: "TermPlot"),
                .product(name: "AnyCodable", package: "AnyCodable"),
                .product(name: "Kitura", package: "Kitura"),
                .product(name: "KituraStencil", package: "KituraStencil"),
                .product(name: "MarkdownKit", package: "MarkdownKit"),
            ]),
        .testTarget(
            name: "wskstatusTests",
            dependencies: ["wskstatus"]),
    ]
)
