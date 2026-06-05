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
    targets: [
        .target(
            name: "NaruRemoteCore",
            path: "NaruRemote/Sources/NaruRemoteCore"
        ),
        .target(
            name: "NaruRemoteApp",
            dependencies: ["NaruRemoteCore"],
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
            dependencies: ["NaruRemoteCore"],
            path: "NaruRemote/Tools/VNCLiveBenchmarkKit"
        ),
        .executableTarget(
            name: "VNCLiveBenchmark",
            dependencies: ["NaruRemoteCore", "VNCLiveBenchmarkKit"],
            path: "NaruRemote/Tools/VNCLiveBenchmark"
        ),
        .executableTarget(
            name: "VNCLiveStimulusWindow",
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
            dependencies: ["VNCLiveBenchmarkKit", "NaruRemoteCore"],
            path: "NaruRemote/Tests/VNCLiveBenchmarkKitTests"
        ),
        .testTarget(
            name: "NaruRemoteBenchmarkTests",
            dependencies: ["NaruRemoteApp", "NaruRemoteCore"],
            path: "NaruRemote/Tests/NaruRemoteBenchmarkTests"
        ),
        .testTarget(
            name: "NaruHelperKitTests",
            dependencies: ["NaruHelperKit", "NaruRemoteCore"],
            path: "NaruHelper/Tests/NaruHelperKitTests"
        )
    ]
)
