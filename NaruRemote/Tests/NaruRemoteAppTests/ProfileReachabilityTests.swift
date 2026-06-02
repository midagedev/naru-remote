import Foundation
import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class ProfileReachabilityTests: XCTestCase {
    func testStoredProfilesStartLaunchReachabilityProbes() async throws {
        let reachable = try ConnectionProfile(displayName: "Alpha Studio", host: "alpha.tailnet.ts.net")
        let password = try ConnectionProfile(displayName: "Bravo Desk", host: "bravo.tailnet.ts.net")
        let offline = try ConnectionProfile(displayName: "Charlie NUC", host: "10.0.0.42")
        let persistence = InMemoryConnectionProfilePersistence(profiles: [offline, password, reachable])
        let profileStore = try await ConnectionProfileStore(persistence: persistence)
        let factory = LaunchReachabilityConnectorFactory(behaviors: [
            .succeed,
            .authenticationRequired,
            .connectionFailed
        ])
        let model = NaruRemoteAppModel(
            profileStore: profileStore,
            connectorFactory: { factory.make() },
            reachabilityProbeTimeout: 0.1,
            reachabilityProbeMaximumConcurrency: 1
        )

        await model.loadStoredProfiles()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(model.snapshot.profileReachability[reachable.id], .reachable)
        XCTAssertEqual(model.snapshot.profileReachability[password.id], .needsPassword)
        XCTAssertEqual(model.snapshot.profileReachability[offline.id], .unreachable(failedStage: .tcp))
        XCTAssertEqual(model.snapshot.connectionGridCards[0].reachability, .reachable)
        XCTAssertEqual(factory.connectorCount, 3)
    }

    func testAddedProfileStartsReachabilityProbe() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let factory = LaunchReachabilityConnectorFactory(behaviors: [.succeed])
        let model = NaruRemoteAppModel(
            connectorFactory: { factory.make() },
            reachabilityProbeTimeout: 0.1
        )

        await model.addProfile(profile)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(model.snapshot.profileReachability[profile.id], .reachable)
        XCTAssertEqual(factory.connectorCount, 1)
    }

    func testProfileDeletionClearsReachabilityState() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                profileReachability: [profile.id: .reachable]
            )
        )

        await model.deleteProfile(id: profile.id)

        XCTAssertNil(model.snapshot.profileReachability[profile.id])
    }

    func testReachabilityProbesDoNotMutateActiveSession() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active, lastFrameAt: Date(timeIntervalSince1970: 10))
        let framebuffer = RFBRawFramebuffer(width: 1, height: 1, fill: RFBColor(red: 9, green: 8, blue: 7))
        let factory = LaunchReachabilityConnectorFactory(behaviors: [.connectionFailed])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            connectorFactory: { factory.make() },
            reachabilityProbeTimeout: 0.1
        )

        model.refreshProfileReachability()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(model.snapshot.session, session)
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffer)
        XCTAssertNil(model.snapshot.diagnosticRun)
        XCTAssertEqual(model.snapshot.profileReachability[profile.id], .unreachable(failedStage: .tcp))
    }

    func testReachabilityProbeConcurrencyIsBounded() async throws {
        let first = try ConnectionProfile(displayName: "Alpha", host: "alpha.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Bravo", host: "bravo.tailnet.ts.net")
        let gate = ProbeGate()
        let persistence = InMemoryConnectionProfilePersistence(profiles: [first, second])
        let profileStore = try await ConnectionProfileStore(persistence: persistence)
        let factory = LaunchReachabilityConnectorFactory(behaviors: [
            .waitThenSucceed(gate),
            .succeed
        ])
        let model = NaruRemoteAppModel(
            profileStore: profileStore,
            connectorFactory: { factory.make() },
            reachabilityProbeTimeout: 0.5,
            reachabilityProbeMaximumConcurrency: 1
        )

        await model.loadStoredProfiles()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(factory.connectorCount, 1)
        XCTAssertEqual(model.snapshot.profileReachability[first.id], .checking)
        XCTAssertEqual(model.snapshot.profileReachability[second.id], .checking)

        gate.signal()
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(factory.connectorCount, 2)
        XCTAssertEqual(model.snapshot.profileReachability[first.id], .reachable)
        XCTAssertEqual(model.snapshot.profileReachability[second.id], .reachable)
    }

    func testStaleReachabilityResultsDoNotOverrideNewProbeGeneration() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let gate = ProbeGate()
        let factory = LaunchReachabilityConnectorFactory(behaviors: [
            .waitThenSucceed(gate),
            .connectionFailed
        ])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { factory.make() },
            reachabilityProbeTimeout: 0.5,
            reachabilityProbeMaximumConcurrency: 1
        )

        model.refreshProfileReachability()
        await waitFor("first reachability probe to start") {
            factory.connectorCount == 1 && gate.isWaiting
        }
        XCTAssertEqual(factory.connectorCount, 1)

        model.refreshProfileReachability()
        await waitFor("new probe generation to publish its result") {
            model.snapshot.profileReachability[profile.id] == .unreachable(failedStage: .tcp)
        }
        XCTAssertEqual(model.snapshot.profileReachability[profile.id], .unreachable(failedStage: .tcp))

        gate.signal()
        await waitFor("stale reachability probe to finish") {
            gate.isFinished
        }

        XCTAssertEqual(factory.connectorCount, 2)
        XCTAssertEqual(model.snapshot.profileReachability[profile.id], .unreachable(failedStage: .tcp))
    }

    private func waitFor(
        _ description: String,
        timeoutMillis: Int = 1_000,
        check: () -> Bool
    ) async {
        if check() {
            return
        }
        let stepMillis = 10
        var elapsed = 0
        while elapsed < timeoutMillis {
            try? await Task.sleep(for: .milliseconds(stepMillis))
            elapsed += stepMillis
            if check() {
                return
            }
        }
        XCTFail("Timed out waiting for \(description)")
    }
}

private enum LaunchReachabilityBehavior: Sendable {
    case succeed
    case authenticationRequired
    case connectionFailed
    case waitThenSucceed(ProbeGate)
}

private final class ProbeGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var isWaiting = false
        var isFinished = false
    }

    var isWaiting: Bool {
        state.withLock(\.isWaiting)
    }

    var isFinished: Bool {
        state.withLock(\.isFinished)
    }

    func wait(timeout: TimeInterval) {
        state.withLock { state in
            state.isWaiting = true
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        state.withLock { state in
            state.isFinished = true
        }
    }

    func signal() {
        semaphore.signal()
    }
}

private final class LaunchReachabilityConnectorFactory: @unchecked Sendable {
    private struct Storage {
        var behaviors: [LaunchReachabilityBehavior]
        var connectors: [FakeLaunchReachabilityConnector] = []
    }

    private let storage: OSAllocatedUnfairLock<Storage>

    init(behaviors: [LaunchReachabilityBehavior]) {
        self.storage = OSAllocatedUnfairLock(initialState: Storage(behaviors: behaviors))
    }

    var connectorCount: Int {
        storage.withLock { $0.connectors.count }
    }

    func make() -> RFBFirstFrameConnecting {
        storage.withLock { storage in
            let behavior = storage.behaviors.isEmpty ? .succeed : storage.behaviors.removeFirst()
            let connector = FakeLaunchReachabilityConnector(behavior: behavior)
            storage.connectors.append(connector)
            return connector
        }
    }
}

private final class FakeLaunchReachabilityConnector: RFBAuthenticatedFirstFrameConnecting, @unchecked Sendable {
    private struct Recording {
        var requests: [Request] = []
        var credentials: [RFBConnectionCredential] = []
    }

    struct Request: Equatable {
        let host: String
        let port: UInt16
    }

    private let behavior: LaunchReachabilityBehavior
    private let recording = OSAllocatedUnfairLock(initialState: Recording())

    init(behavior: LaunchReachabilityBehavior) {
        self.behavior = behavior
    }

    var state: RFBClientState { .disconnected }
    var lastFrame: RFBFrameMetadata? { nil }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectFirstFrame(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        recording.withLock { state in
            state.requests.append(Request(host: host, port: port))
            state.credentials.append(credential)
        }

        switch behavior {
        case .succeed:
            return Self.makeServerInit()
        case .authenticationRequired:
            throw RFBNetworkClientError.authenticationRequired([RFBSecurityType.vncAuthentication.rawValue])
        case .connectionFailed:
            throw RFBNetworkClientError.connectionFailed
        case .waitThenSucceed(let gate):
            gate.wait(timeout: timeout)
            return Self.makeServerInit()
        }
    }

    private static func makeServerInit() -> RFBServerInit {
        RFBServerInit(
            width: 1440,
            height: 900,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: "Reachability Fixture"
        )
    }
}
