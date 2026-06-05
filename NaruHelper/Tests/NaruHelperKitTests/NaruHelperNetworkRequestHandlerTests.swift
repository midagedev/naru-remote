import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperNetworkRequestHandlerTests: XCTestCase {
    func testNetworkClientCanCallRunningHelperServer() async throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let port: UInt16 = 45974
        let recorder = InsertRecorder()
        let handler = makeHandler(expectedPairingSecret: "expected") { request in
            recorder.record(request.text)
            return NaruHelperInsertTextResponse(
                requestID: request.requestID,
                status: .sent,
                strategyUsed: .pasteboardPasteWithRestore
            )
        }
        let server = try NaruHelperNetworkServer(port: port, handler: handler)
        server.start()
        defer { server.cancel() }
        try await Task.sleep(nanoseconds: 50_000_000)

        let client = NaruHelperNetworkTextInsertClient(
            host: "127.0.0.1",
            port: port,
            pairingSecret: "expected",
            timeout: 1
        )

        let capability = try await client.capability()
        let result = try await client.insertText(
            "한글과 English",
            metadata: HelperTextInsertRequestMetadata(
                id: requestID,
                sessionID: requestID,
                payloadEncoding: .utf8ExtensionRequired,
                payloadSizeBucket: .small
            )
        )

        XCTAssertEqual(capability.availability, .reachable)
        XCTAssertEqual(result.status, .sent)
        XCTAssertEqual(result.safeFailureCode, .none)
        XCTAssertEqual(recorder.insertedTexts, ["한글과 English"])
    }

    func testCapabilityRequiresMatchingPairingSecret() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let handler = makeHandler(expectedPairingSecret: "expected")

        let response = handler.handle(NaruHelperNetworkRequest(
            requestID: requestID,
            command: .capability,
            pairingSecret: "wrong",
            capabilityRequest: NaruHelperNetworkCapabilityRequest()
        ))

        XCTAssertEqual(response.requestID, requestID)
        XCTAssertNil(response.capabilityResponse)
        XCTAssertEqual(response.safeFailureCode, .revoked)
    }

    func testCapabilityReturnsFixedCatalogPermissionState() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"))
        let handler = makeHandler(expectedPairingSecret: "expected")

        let response = handler.handle(NaruHelperNetworkRequest(
            requestID: requestID,
            command: .capability,
            pairingSecret: "expected",
            capabilityRequest: NaruHelperNetworkCapabilityRequest()
        ))

        XCTAssertEqual(response.requestID, requestID)
        XCTAssertEqual(response.capabilityResponse?.availability, .reachable)
        XCTAssertEqual(response.capabilityResponse?.permissionState.accessibility, "granted")
        XCTAssertEqual(response.safeFailureCode, .none)
    }

    func testInsertRoutesToConfiguredInserter() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"))
        let recorder = InsertRecorder()
        let handler = makeHandler(expectedPairingSecret: "expected") { request in
            recorder.record(request.text)
            return NaruHelperInsertTextResponse(
                requestID: request.requestID,
                status: .sent,
                strategyUsed: .pasteboardPasteWithRestore
            )
        }

        let response = handler.handle(NaruHelperNetworkRequest(
            requestID: requestID,
            command: .insertText,
            pairingSecret: "expected",
            insertRequest: NaruHelperInsertTextRequest(
                requestID: requestID,
                payloadEncoding: .utf8ExtensionRequired,
                payloadSizeBucket: .small,
                text: "한글과 English"
            )
        ))

        XCTAssertEqual(recorder.insertedTexts, ["한글과 English"])
        XCTAssertEqual(response.insertResponse?.status, .sent)
        XCTAssertEqual(response.safeFailureCode, .none)
    }

    func testRevokeBlocksFutureRequestsInSameHelperProcess() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        let revocationStore = InMemoryNaruHelperPairingRevocationStore()
        let handler = makeHandler(
            expectedPairingSecret: "expected",
            revocationStore: revocationStore
        )

        let revoke = handler.handle(NaruHelperNetworkRequest(
            requestID: requestID,
            command: .revokePairing,
            pairingSecret: "expected"
        ))
        let capability = handler.handle(NaruHelperNetworkRequest(
            requestID: requestID,
            command: .capability,
            pairingSecret: "expected",
            capabilityRequest: NaruHelperNetworkCapabilityRequest()
        ))

        XCTAssertEqual(revoke.safeFailureCode, .revoked)
        XCTAssertEqual(capability.safeFailureCode, .revoked)
        XCTAssertNil(capability.capabilityResponse)
    }

    private func makeHandler(
        expectedPairingSecret: String,
        revocationStore: any NaruHelperPairingRevocationStore = InMemoryNaruHelperPairingRevocationStore(),
        insertHandler: @escaping @Sendable (NaruHelperInsertTextRequest) -> NaruHelperInsertTextResponse = { request in
            NaruHelperInsertTextResponse(
                requestID: request.requestID,
                status: .failed,
                strategyUsed: .unsupported,
                safeFailureCode: .insertRejected
            )
        }
    ) -> NaruHelperNetworkRequestHandler {
        NaruHelperNetworkRequestHandler(
            expectedPairingSecret: expectedPairingSecret,
            revocationStore: revocationStore,
            capabilityProvider: {
                NaruHelperCapabilityResponse(
                    availability: .reachable,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "granted",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.pasteboardPasteWithRestore]
                )
            },
            insertHandler: insertHandler
        )
    }
}

private final class InsertRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []

    var insertedTexts: [String] {
        lock.withLock { texts }
    }

    func record(_ text: String) {
        lock.withLock {
            texts.append(text)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
