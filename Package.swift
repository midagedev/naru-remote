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
        .testTarget(
            name: "NaruRemoteCoreTests",
            dependencies: ["NaruRemoteCore"],
            path: "NaruRemote/Tests/NaruRemoteCoreTests"
        ),
        .testTarget(
            name: "NaruRemoteAppTests",
            dependencies: ["NaruRemoteApp", "NaruRemoteCore"],
            path: "NaruRemote/Tests/NaruRemoteAppTests"
        ),
        .testTarget(
            name: "FakeRFBServerKitTests",
            dependencies: ["FakeRFBServerKit", "NaruRemoteCore"],
            path: "NaruRemote/Tests/FakeRFBServerKitTests"
        )
    ]
)
