// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Toolkit",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SMCCore", path: "SMCCore", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "TouchBarBridge", path: "TouchBarBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(
            name: "Toolkit",
            dependencies: ["SMCCore", "TouchBarBridge"],
            path: "Sources/Toolkit",
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
