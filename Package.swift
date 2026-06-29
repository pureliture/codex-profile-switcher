// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexProfileSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexProfileSwitcherCore", targets: ["CodexProfileSwitcherCore"]),
        .executable(name: "CodexProfileSwitcherApp", targets: ["CodexProfileSwitcherApp"]),
        .executable(name: "CodexProfileSwitcherCoreTests", targets: ["CodexProfileSwitcherCoreTests"])
    ],
    targets: [
        .target(name: "CodexProfileSwitcherCore"),
        .executableTarget(
            name: "CodexProfileSwitcherApp",
            dependencies: ["CodexProfileSwitcherCore"]
        ),
        .executableTarget(
            name: "CodexProfileSwitcherCoreTests",
            dependencies: ["CodexProfileSwitcherCore"]
        )
    ]
)
