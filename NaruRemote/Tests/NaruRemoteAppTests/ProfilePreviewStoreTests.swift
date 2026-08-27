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

    func testSaveThumbnailExcludesDirectoryFromICloudBackup() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let store = FileProfilePreviewStore(directoryURL: directoryURL)

        try await store.saveThumbnail(makeThumbnail(red: 33), for: UUID())

        let values = try directoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
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

    // MARK: - Downsampling quality (spec 038 FR-010 / FR-011)

    /// The founder: "호스트목록화면에서 프리뷰 이미지 품질이 아주 낮은데 리사이즈
    /// 방식문제일지". It was.
    ///
    /// A one-pixel checkerboard is the cleanest way to separate the two
    /// possible resizers, because they cannot agree on it: averaging any even
    /// block gives the mid-grey of the two colours, while sampling a single
    /// source pixel gives one of the two originals and nothing in between.
    /// That difference is exactly what desktop text looked like — strokes kept
    /// or dropped by where the sample happened to land, which reads as noise
    /// rather than as a smaller picture.
    func testDownsamplingAveragesTheBlockInsteadOfSamplingOnePixelOfIt() throws {
        let width = 640
        let height = 400
        var pixels: [RFBColor] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(
                    (x + y).isMultiple(of: 2)
                        ? RFBColor(red: 0, green: 0, blue: 0)
                        : RFBColor(red: 255, green: 255, blue: 255)
                )
            }
        }
        let framebuffer = RFBRawFramebuffer(width: width, height: height, pixels: pixels)

        // 640x400 -> 160x100 is an exact 4x reduction, so every destination
        // pixel covers a 4x4 block holding eight black and eight white.
        let thumbnail = try XCTUnwrap(
            ProfilePreviewThumbnail(
                framebuffer: framebuffer,
                maxWidth: 160,
                maxHeight: 100
            )
        )

        XCTAssertEqual(thumbnail.width, 160)
        XCTAssertEqual(thumbnail.height, 100)
        for pixel in thumbnail.pixels {
            XCTAssertEqual(
                Int(pixel.red),
                128,
                accuracy: 1,
                "A checkerboard averages to mid-grey; 0 or 255 means one pixel was sampled"
            )
        }
    }

    /// FR-011: the cap is large enough that a grid card is not magnifying its
    /// own thumbnail on a 3x phone.
    func testTheDefaultCapCoversAGridCardWithoutUpscaling() {
        // A card is about half of a 402pt-wide iPhone; at 3x that is ~570px,
        // and the cap deliberately stops a little short of it (the comment on
        // `defaultMaxWidth` records why).
        XCTAssertGreaterThanOrEqual(ProfilePreviewThumbnail.defaultMaxWidth, 480)
        XCTAssertEqual(
            Double(ProfilePreviewThumbnail.defaultMaxWidth)
                / Double(ProfilePreviewThumbnail.defaultMaxHeight),
            1.6,
            accuracy: 1e-9,
            "The cap keeps a 16:10 shape so a typical desktop is bounded by width"
        )
    }
}
