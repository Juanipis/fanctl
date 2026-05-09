// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fanctl",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SMCKit", targets: ["SMCKit"]),
        .library(name: "FanCtlProtocol", targets: ["FanCtlProtocol"]),
        .executable(name: "fanctl-cli", targets: ["fanctl-cli"]),
        .executable(name: "FanCtlHelper", targets: ["FanCtlHelper"]),
        .executable(name: "FanCtlApp", targets: ["FanCtlApp"]),
    ],
    targets: [
        .target(name: "SMCKit"),

        .target(name: "FanCtlProtocol"),

        .executableTarget(
            name: "fanctl-cli",
            dependencies: ["SMCKit"]
        ),

        .executableTarget(
            name: "FanCtlHelper",
            dependencies: ["SMCKit", "FanCtlProtocol"]
        ),

        .executableTarget(
            name: "FanCtlApp",
            dependencies: ["SMCKit", "FanCtlProtocol"]
        ),

        .testTarget(
            name: "SMCKitTests",
            dependencies: ["SMCKit"]
        ),
    ]
)
