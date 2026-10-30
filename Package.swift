// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskJump",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CGSPrivate"),
        .executableTarget(
            name: "DeskJump",
            dependencies: ["CGSPrivate"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]
        ),
    ]
)
