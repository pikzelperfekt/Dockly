// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dockly",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Dockly",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Dockly",
            linkerSettings: [
                // Weak-link CoreAudio so the macOS-14.4 process-tap class
                // (CATapDescription) is a weak symbol — null on macOS 13 instead
                // of blocking launch. DJ mode stays #available-guarded at runtime.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "CoreAudio"])
            ]
        )
    ]
)
