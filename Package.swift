// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
]
/// The app runs on the main thread, except for the AX app threads, the socket server and the signal handlers.
/// Code that runs there is marked `nonisolated`
let mainActorSwiftSettings: [SwiftSetting] = swiftSettings + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "AeroSpacePackage",
    // Also the deployment target of the CLI. The app's is in xcode/project.yml
    platforms: [.macOS("27.0")], // `.v27` needs swift-tools-version 6.4
    // Products define the executables and libraries a package produces, making them visible to other packages.
    products: [
        .executable(name: "aerospace", targets: ["Cli"]),
        // Don't use this build for release, use xcode instead
        .executable(name: "AeroSpaceApp", targets: ["AeroSpaceApp"]),
        // We only need to expose this as a product for xcode
        .library(name: "AppBundle", targets: ["AppBundle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/InerziaSoft/ISSoundAdditions.git", exact: "2.0.1"),
        .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.4"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.3.0"),
        .package(url: "https://github.com/soffes/HotKey.git", exact: "0.2.1"),
    ],
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    targets: [
        // Exposes the private _AXUIElementGetWindow function to swift
        .target(
            name: "PrivateApi",
            path: "Sources/PrivateApi",
            publicHeadersPath: "include",
        ),
        .target(
            name: "Common",
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "AppBundle",
            dependencies: [
                // Only the module that is used: the `Collections` umbrella builds all of swift-collections (64k lines)
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "ISSoundAdditions", package: "ISSoundAdditions"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
                .target(name: "Common"),
                .target(name: "PrivateApi"),
            ],
            swiftSettings: mainActorSwiftSettings,
        ),
        .executableTarget(
            name: "AeroSpaceApp",
            dependencies: [
                .target(name: "AppBundle"),
            ],
            swiftSettings: mainActorSwiftSettings,
        ),
        .executableTarget(
            name: "Cli",
            dependencies: [
                .target(name: "Common"),
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "AppBundleTests",
            dependencies: [
                .target(name: "AppBundle"),
            ],
            swiftSettings: mainActorSwiftSettings,
        ),
    ],
)
