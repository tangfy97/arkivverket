// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Arkiv",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Arkiv", targets: ["Arkiv"])
    ],
    targets: [
        .executableTarget(
            name: "Arkiv",
            path: "Sources/Arkiv",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
