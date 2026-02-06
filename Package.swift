// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Chunkpad",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        // MLX Embedders for on-device embedding inference (includes MLX, MLXNN, Tokenizers)
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.29.1"),
    ],
    targets: [
        // C target: sqlite-vec compiled against the system SQLite
        .target(
            name: "CSQLiteVec",
            path: "Vendor/CSQLiteVec",
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_CORE"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),

        // Main app target
        .executableTarget(
            name: "Chunkpad",
            dependencies: [
                "CSQLiteVec",
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
            ],
            path: "Chunkpad",
            exclude: [
                "Resources/Info.plist",
                "Resources/Chunkpad.entitlements",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
