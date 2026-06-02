import Foundation
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

final class ProfilePreviewStoreTests: XCTestCase {
    func testThumbnailDownsamplesFramebufferAndCreatesImage() throws {
        let framebuffer = RFBRawFramebuffer(
            width: 640,
            height: 400,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )

        let thumbnail = try XCTUnwrap(
            ProfilePreviewThumbnail(
                framebuffer: framebuffer,
                capturedAt: Date(timeIntervalSince1970: 100),
                maxWidth: 64,
                maxHeight: 40
            )
        )

        XCTAssertEqual(thumbnail.width, 64)
        XCTAssertEqual(thumbnail.height, 40)
        XCTAssertEqual(thumbnail.sourceWidth, 640)
        XCTAssertEqual(thumbnail.sourceHeight, 400)
        XCTAssertEqual(thumbnail.pixels.count, 64 * 40)
        XCTAssertNotNil(thumbnail.cgImage)
    }

    func testInMemoryPreviewStoreRoundTripsAndDeletesByProfileID() async throws {
        let profileID = UUID()
        let thumbnail = makeThumbnail(red: 11)
        let store = InMemoryProfilePreviewStore()

        try await store.saveThumbnail(thumbnail, for: profileID)

        let loaded = try await store.loadThumbnail(for: profileID)
        XCTAssertEqual(loaded, thumbnail)

        try await store.deleteThumbnail(for: profileID)

        let deleted = try await store.loadThumbnail(for: profileID)
        XCTAssertNil(deleted)
    }

    func testFilePreviewStoreRoundTripsAndDeletesByProfileID() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let profileID = UUID()
        let thumbnail = makeThumbnail(red: 22)
        let store = FileProfilePreviewStore(directoryURL: directoryURL)

        try await store.saveThumbnail(thumbnail, for: profileID)

        let reloaded = try await FileProfilePreviewStore(directoryURL: directoryURL)
            .loadThumbnail(for: profileID)
        XCTAssertEqual(reloaded, thumbnail)

        try await store.deleteThumbnail(for: profileID)

        let deleted = try await store.loadThumbnail(for: profileID)
        XCTAssertNil(deleted)
    }

    private func makeThumbnail(red: UInt8) -> ProfilePreviewThumbnail {
        ProfilePreviewThumbnail(
            width: 2,
            height: 1,
            sourceWidth: 4,
            sourceHeight: 2,
            capturedAt: Date(timeIntervalSince1970: 200),
            pixels: [
                RFBColor(red: red, green: 1, blue: 2),
                RFBColor(red: red, green: 3, blue: 4)
            ]
        )
    }
}
