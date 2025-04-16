// swift-tools-version:5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftSchemaForge",
    platforms: [
        .macOS(.v13) // Using macOS 13 as minimum, adjust if needed (e.g., .v14)
    ],
    dependencies: [
        // Dependency for parsing Swift code
        .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1"),
        // Dependency for parsing command-line arguments
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // Define the executable target
        .executableTarget(
            name: "SwiftSchemaForge", // The name of your executable module
            dependencies: [
                // Depend on products from the declared package dependencies
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                // ---- ADDED THIS LINE ----
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
            // SPM generally finds Sources/main.swift correctly by default
        ),
    ]
)
