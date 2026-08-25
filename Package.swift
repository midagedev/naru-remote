// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NaruRemote",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NaruRemoteCore",
            targets: ["NaruRemoteCore"]
        ),
        .library(
            name: "NaruRemoteApp",
            targets: ["NaruRemoteApp"]
        ),
        .executable(
            name: "FakeRFBServer",
            targets: ["FakeRFBServer"]
        ),
        .executable(
            name: "VNCLiveBenchmark",
            targets: ["VNCLiveBenchmark"]
        ),
        .executable(
            name: "VNCLiveStimulusWindow",
            targets: ["VNCLiveStimulusWindow"]
        ),
        .executable(
            name: "NaruHelper",
            targets: ["NaruHelper"]
        )
    ],
    dependencies: [
        // The four touchscreen-input state machines, shared with gadak's phone
        // client through golden vectors rather than through a binary. These
        // types were lifted from this repository; depending on them here is
        // what makes "one Swift implementation" true rather than aspirational.
        .package(url: "https://github.com/midagedev/glasskeys.git", from: "0.2.2")
    ],
    targets: [
        .target(
            name: "NaruRemoteCore",
            dependencies: [.product(name: "Glasskeys", package: "glasskeys")],
            path: "NaruRemote/Sources/NaruRemoteCore"
        ),
        .target(
            name: "NaruRemoteApp",
            dependencies: ["NaruRemoteCore", .product(name: "Glasskeys", package: "glasskeys")],
            path: "NaruRemote/App"
        ),
        .target(
            name: "FakeRFBServerKit",
            path: "TestFixtures/FakeRFBServer/ServerKit"
        ),
        .executableTarget(
            name: "FakeRFBServer",
            dependencies: ["FakeRFBServerKit"],
            path: "TestFixtures/FakeRFBServer/Executable"
        ),
        .target(
            name: "VNCLiveBenchmarkKit",
            dependencies: ["NaruRemoteCore", "NaruHelperKit"],
            path: "NaruRemote/Tools/VNCLiveBenchmarkKit"
        ),
        .executableTarget(
            name: "VNCLiveBenchmark",
            dependencies: ["NaruRemoteCore", "VNCLiveBenchmarkKit"],
            path: "NaruRemote/Tools/VNCLiveBenchmark"
        ),
        .executableTarget(
            name: "FrameSizeProbe",
            dependencies: ["NaruRemoteCore"],
            path: "NaruRemote/Tools/FrameSizeProbe"
        ),
        .executableTarget(
            name: "VNCLiveStimulusWindow",
            dependencies: ["VNCLiveBenchmarkKit"],
            path: "NaruRemote/Tools/VNCLiveStimulusWindow"
        ),
        .target(
            name: "NaruHelperKit",
            dependencies: ["NaruRemoteCore"],
            path: "NaruHelper/Sources/NaruHelperKit"
        ),
        .executableTarget(
            name: "NaruHelper",
            dependencies: ["NaruHelperKit"],
            path: "NaruHelper/Sources/NaruHelper"
        ),
        .testTarget(
            name: "NaruRemoteCoreTests",
            dependencies: ["NaruRemoteCore"],
            path: "NaruRemote/Tests/NaruRemoteCoreTests"
        ),
        .testTarget(
            name: "NaruRemoteAppTests",
            dependencies: ["NaruRemoteApp", "NaruRemoteCore", "NaruHelperKit"],
            path: "NaruRemote/Tests/NaruRemoteAppTests"
        ),
        .testTarget(
            name: "FakeRFBServerKitTests",
            dependencies: ["FakeRFBServerKit", "NaruRemoteCore"],
            path: "NaruRemote/Tests/FakeRFBServerKitTests"
        ),
        .testTarget(
            name: "VNCLiveBenchmarkKitTests",
            dependencies: ["VNCLiveBenchmarkKit", "NaruRemoteCore", "NaruHelperKit"],
            path: "NaruRemote/Tests/VNCLiveBenchmarkKitTests"
        ),
        .testTarget(
            name: "NaruRemoteBenchmarkTests",
            dependencies: [
                "NaruRemoteApp",
                "NaruRemoteCore",
                .target(name: "NaruHelperKit", condition: .when(platforms: [.macOS]))
            ],
            path: "NaruRemote/Tests/NaruRemoteBenchmarkTests"
        ),
        .testTarget(
            name: "NaruHelperKitTests",
            dependencies: ["NaruHelperKit", "NaruRemoteCore"],
            path: "NaruHelper/Tests/NaruHelperKitTests"
        )
    ]
)
