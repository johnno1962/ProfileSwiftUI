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
                 .upToNextMinor(from: "8.5.3")),
        .package(url: "https://github.com/johnno1962/SwiftRegex5",
                 .upToNextMinor(from: "6.1.0")),
        .package(url: "https://github.com/johnno1962/DLKit",
                 .upToNextMinor(from: "3.3.4")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ProfileSwiftUI", dependencies: ["SwiftTrace", 
                .product(name: "DLKitC", package: "DLKit"), "SwiftRegex"]),
    ]
)
