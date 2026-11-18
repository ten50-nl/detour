// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Detour",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Detour", targets: ["Detour"]),
        .executable(name: "detour-cli", targets: ["DetourCLI"]),
        .library(name: "DetourCore", targets: ["DetourCore"]),
    ],
    targets: [
        .target(
            name: "DetourCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Detour",
            dependencies: ["DetourCore"]
        ),
        .executableTarget(
            name: "DetourCLI",
            dependencies: ["DetourCore"]
        ),
        .testTarget(
            name: "DetourCoreTests",
            dependencies: ["DetourCore"]
        ),
    ]
)
