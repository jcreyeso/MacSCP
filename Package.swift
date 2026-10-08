// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacSCP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacSCP", targets: ["MacSCP"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacSCP",
            path: "MacSCP",
            exclude: [
                "Resources/Info.plist",
                "Resources/MacSCP.entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .process("Resources/AppIcon.icns")
            ]
        )
    ]
)

