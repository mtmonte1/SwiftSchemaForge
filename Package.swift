// swift-tools-version:5.10 // Good, matches Swift version used
import PackageDescription

let package = Package(
    name: "SwiftSchemaForge", // Correct name
    platforms: [
        .macOS(.v13) // Sensible minimum requirement for recent Swift features
    ],
    dependencies: [
        // SwiftSyntax: Correctly specified, version aligns with toolchain
        .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1"),
        // ArgumentParser: Correctly specified, reasonable version constraint
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftSchemaForge", // Matches package name
            dependencies: [
                 // Links to the necessary product modules from the dependencies
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"), // For Parser.parse
                .product(name: "ArgumentParser", package: "swift-argument-parser"), // For CLI
                .product(name: "SwiftDiagnostics", package: "swift-syntax"), // Needed for Diagnostic type if we use it
            ]
             // No need for explicit `path: "Sources"` as structure is standard
        ),
         // No Test Target Defined yet - this is a potential addition later
    ]
)
