// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkyNear",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SkyNear", targets: ["SkyNear"]),
        .library(name: "SkyNearWidgets", targets: ["SkyNearWidgets"])
    ],
    targets: [
        .target(name: "RadarCore", resources: [.process("Resources")]),
        .target(
            name: "SkyNear",
            dependencies: ["RadarCore"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-cross-import-overlays"])
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-headerpad", "-Xlinker", "0x4000"])
            ]
        ),
        .target(
            name: "SkyNearWidgets",
            dependencies: ["RadarCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-headerpad", "-Xlinker", "0x4000",
                    "-Xlinker", "-u", "-Xlinker", "_main"
                ])
            ]
        ),
        .testTarget(name: "RadarCoreTests", dependencies: ["RadarCore"])
    ],
    swiftLanguageModes: [.v6]
)
