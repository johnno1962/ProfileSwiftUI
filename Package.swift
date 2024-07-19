// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ProfileSwiftUI",
    platforms: [.macOS("10.12"), .iOS("10.0"), .tvOS("10.0")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ProfileSwiftUI",
            targets: ["ProfileSwiftUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/johnno1962/SwiftTrace",
                 .upToNextMajor(from: "8.6.0")),
        .package(url: "https://github.com/johnno1962/SwiftRegex5",
                 .upToNextMajor(from: "6.1.0")),
        .package(url: "https://github.com/johnno1962/DLKit",
                 .upToNextMajor(from: "3.4.3")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ProfileSwiftUI", dependencies: [
                .product(name: "SwiftTraceD", package: "SwiftTrace"),
                .product(name: "DLKitCD", package: "DLKit"), "SwiftRegex"]),
    ]
)
