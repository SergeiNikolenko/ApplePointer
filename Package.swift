// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ApplePointer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ApplePointerCore",
            targets: ["ApplePointerCore"]
        ),
        .executable(
            name: "ApplePointer",
            targets: ["ApplePointer"]
        )
    ],
    targets: [
        .target(
            name: "ApplePointerCore",
            path: "Sources/ApplePointerCore"
        ),
        .executableTarget(
            name: "ApplePointer",
            dependencies: ["ApplePointerCore"],
            path: "Sources/ApplePointer",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "ApplePointerCoreTests",
            dependencies: ["ApplePointerCore"],
            path: "Tests/ApplePointerCoreTests"
        )
    ]
)
