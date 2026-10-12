// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypeSwitch",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "TypeSwitch",
            targets: ["TypeSwitchApp"]
        ),
        .executable(
            name: "TypeSwitchTestHost",
            targets: ["TypeSwitchTestHost"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TypeSwitchApp",
            path: "Sources/TypeSwitchApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TypeSwitchTestHost",
            path: "Sources/TypeSwitchTestHost"
        ),
        .testTarget(
            name: "TypeSwitchTests",
            dependencies: ["TypeSwitchApp"],
            path: "Tests/TypeSwitchTests"
        )
    ]
)
