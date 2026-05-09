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
            dependencies: ["SMCKit", "FanCtlProtocol"],
            swiftSettings: [
                // SwiftUI + ObservableObject + XPC reply blocks crossing
                // queues trips Swift 6's strict isolation checks even when
                // we mark `@unchecked Sendable`. The rest of the package
                // stays in Swift 6.
                .swiftLanguageMode(.v5)
            ]
        ),

        .testTarget(
            name: "SMCKitTests",
            dependencies: ["SMCKit"]
        ),
    ]
)
