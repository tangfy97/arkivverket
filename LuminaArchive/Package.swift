// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LuminaArchive",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LuminaArchive", targets: ["LuminaArchive"])
    ],
    targets: [
        .executableTarget(
            name: "LuminaArchive",
            path: "Sources/LuminaArchive",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
