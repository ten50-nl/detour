// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Detour",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Detour", targets: ["Detour"]),
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
        .testTarget(
            name: "DetourCoreTests",
            dependencies: ["DetourCore"]
        ),
    ]
)
