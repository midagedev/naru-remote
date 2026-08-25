import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(Metal) && canImport(MetalKit)
import Metal
import MetalKit

@MainActor
final class MetalFramebufferRendererTests: XCTestCase {
    private func requireDevice() throws -> MTLDevice {
        try XCTSkipUnless(
            MTLCreateSystemDefaultDevice() != nil,
            "Metal device unavailable on this CI host."
        )
        return MTLCreateSystemDefaultDevice()!
    }

    // MARK: - Texture lifecycle

    func testRendererCreatesTextureMatchingFramebufferDimensions() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        let framebuffer = RFBRawFramebuffer(
            width: 4,
            height: 3,
            fill: RFBColor(red: 10, green: 20, blue: 30, alpha: 255)
        )

        renderer.enqueue(framebuffer)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let size = try XCTUnwrap(renderer.currentTextureSize)
        XCTAssertEqual(size.width, 4)
        XCTAssertEqual(size.height, 3)
    }

    func testRendererPreservesRGBAByteOrder() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 200, green: 100, blue: 50, alpha: 240)
        )

        renderer.enqueue(framebuffer)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        XCTAssertEqual(bytes.count, 8)
        // RGBA8Unorm stores red, green, blue, alpha in that byte order
        // — round-trip a known pattern so we catch any accidental
        // swizzle in the upload path.
        XCTAssertEqual(bytes[0], 200, "red byte 0")
        XCTAssertEqual(bytes[1], 100, "green byte 1")
        XCTAssertEqual(bytes[2], 50, "blue byte 2")
        XCTAssertEqual(bytes[3], 240, "alpha byte 3")
        XCTAssertEqual(bytes[4], 200, "red byte 4 (second pixel)")
        XCTAssertEqual(bytes[5], 100)
        XCTAssertEqual(bytes[6], 50)
        XCTAssertEqual(bytes[7], 240)
    }

    func testRendererRecreatesTextureWhenDimensionsChange() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 10, green: 0, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        let firstSize = try XCTUnwrap(renderer.currentTextureSize)
        XCTAssertEqual(firstSize.width, 4)
        XCTAssertEqual(firstSize.height, 4)

        renderer.enqueue(
            RFBRawFramebuffer(width: 8, height: 2, fill: RFBColor(red: 0, green: 30, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        let secondSize = try XCTUnwrap(renderer.currentTextureSize)
        XCTAssertEqual(secondSize.width, 8)
        XCTAssertEqual(secondSize.height, 2)

        // The full readback must reflect the new dimensions — a partial
        // overwrite of a stale 4x4 texture would leave residue.
        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        XCTAssertEqual(bytes.count, 8 * 2 * 4)
        XCTAssertEqual(bytes[1], 30, "every pixel should be the new green fill")
        XCTAssertEqual(bytes[bytes.count - 3], 30)
    }

    func testRendererIgnoresZeroSizedFramebuffers() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        renderer.enqueue(RFBRawFramebuffer(width: 0, height: 0))
        XCTAssertFalse(
            renderer.uploadPendingFramebufferForTesting(),
            "Zero-size framebuffers must not allocate a texture."
        )
        XCTAssertNil(renderer.currentTextureSize)
    }

    func testRendererClearFramebuffersDropsTextureAndPendingUpload() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 10, green: 0, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(renderer.currentTextureSize?.width, 4)

        renderer.enqueue(
            RFBRawFramebuffer(width: 8, height: 4, fill: RFBColor(red: 20, green: 0, blue: 0))
        )
        renderer.clearFramebuffers()

        XCTAssertNil(renderer.currentTextureSize)
        XCTAssertNil(renderer.lastUploadMilliseconds)
        XCTAssertFalse(
            renderer.uploadPendingFramebufferForTesting(),
            "A clear event should discard stale pending pixels instead of uploading them after disconnect."
        )
    }

    func testSuspendedRendererAllowsOneThrottledUploadBypass() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        renderer.setPendingFramebufferUploadSuspended(true)
        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 10, green: 0, blue: 0))
        )

        XCTAssertFalse(
            renderer.uploadPendingFramebufferRespectingSuspensionForTesting(),
            "Gesture suspension should hold pending frames unless the viewport host grants a throttled bypass."
        )
        XCTAssertNil(renderer.currentTextureSize)

        renderer.allowNextPendingFramebufferUploadWhileSuspended()
        XCTAssertTrue(renderer.uploadPendingFramebufferRespectingSuspensionForTesting())
        XCTAssertEqual(renderer.currentTextureSize?.width, 4)

        renderer.enqueue(
            RFBRawFramebuffer(width: 8, height: 4, fill: RFBColor(red: 0, green: 20, blue: 0))
        )
        XCTAssertFalse(
            renderer.uploadPendingFramebufferRespectingSuspensionForTesting(),
            "The bypass is single-use so active gestures cannot accidentally upload every incoming frame."
        )
        XCTAssertEqual(renderer.currentTextureSize?.width, 4)

        renderer.setPendingFramebufferUploadSuspended(false)
        XCTAssertTrue(renderer.uploadPendingFramebufferRespectingSuspensionForTesting())
        XCTAssertEqual(renderer.currentTextureSize?.width, 8)
    }

    // MARK: - Presentation ledger (spec 028)

    func testASuspendedRendererNamesTheReasonFramesAreNotReachingTheScreen() throws {
        // Spec 028. Before the ledger, this state incremented nothing at all:
        // the pump could run at full rate, the frame counter the liveness gate
        // asserts could climb, and the screen would sit frozen with no counter
        // anywhere disagreeing. That is what made the same freeze class
        // survivable twice.
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        renderer.setSuspensionWatchdogIntervalForTesting(nanoseconds: .max)
        renderer.setPendingFramebufferUploadSuspended(true)

        for index in 0..<12 {
            renderer.recordPublishedFrame()
            renderer.enqueue(
                RFBRawFramebuffer(
                    width: 4,
                    height: 4,
                    fill: RFBColor(red: UInt8(index), green: 0, blue: 0)
                )
            )
            XCTAssertFalse(renderer.uploadPendingFramebufferRespectingSuspensionForTesting())
        }

        let ledger = renderer.presentationLedger
        XCTAssertEqual(ledger.publishedCount, 12)
        XCTAssertEqual(ledger.count(.presented), 0)
        XCTAssertTrue(ledger.isPresentationStalled(minimumPublished: 10))
        XCTAssertEqual(
            ledger.dominantWithholdingReason,
            .heldBySuspension,
            "A frozen screen must arrive already attributed, not start an investigation."
        )
        XCTAssertTrue(ledger.isBalanced)
    }

    func testTheSuspensionLatchReleasesItselfOnceTheWatchdogExpires() throws {
        // Spec 028 FR-004. `isPendingFramebufferUploadSuspended` had no release
        // path other than the gesture-finish that set it. If that finish did not
        // run, presentation stopped for the rest of the session.
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        // The two phases are driven by the interval, not by sleeping: a
        // wall-clock margin here would be a flake on a loaded machine, and a
        // flaky watchdog test is worse than none.
        renderer.setSuspensionWatchdogIntervalForTesting(nanoseconds: .max)
        renderer.setPendingFramebufferUploadSuspended(true)
        renderer.recordPublishedFrame()
        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 10, green: 0, blue: 0))
        )

        XCTAssertFalse(
            renderer.uploadPendingFramebufferRespectingSuspensionForTesting(),
            "The latch must still hold before the watchdog interval elapses."
        )
        XCTAssertEqual(renderer.presentationLedger.watchdogReleaseCount, 0)

        renderer.setSuspensionWatchdogIntervalForTesting(nanoseconds: 0)

        XCTAssertTrue(
            renderer.uploadPendingFramebufferRespectingSuspensionForTesting(),
            "A latch held past its bound must release itself rather than freeze the session."
        )
        XCTAssertEqual(renderer.presentationLedger.watchdogReleaseCount, 1)
        XCTAssertEqual(renderer.presentationLedger.count(.presented), 1)
        XCTAssertEqual(renderer.currentTextureSize?.width, 4)
    }

    func testPresentationIsClaimedOnlyWherePixelsReachTheTexture() throws {
        // Spec 028 FR-003. Enqueuing is not presenting — that conflation is what
        // the existing liveness gate is built on.
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        renderer.recordPublishedFrame()
        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 10, green: 0, blue: 0))
        )
        XCTAssertEqual(
            renderer.presentationLedger.count(.presented),
            0,
            "A frame that has only been enqueued has not been presented."
        )

        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(renderer.presentationLedger.count(.presented), 1)
        XCTAssertTrue(renderer.presentationLedger.isBalanced)
    }

    func testAFrameReplacedBeforePresentationIsCountedAsSuperseded() throws {
        // Spec 028. Shedding load is legitimate; shedding it invisibly is what
        // makes a stall indistinguishable from a healthy session.
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        for index in 0..<3 {
            renderer.recordPublishedFrame()
            renderer.enqueue(
                RFBRawFramebuffer(
                    width: 4,
                    height: 4,
                    fill: RFBColor(red: UInt8(index), green: 0, blue: 0)
                )
            )
        }
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let ledger = renderer.presentationLedger
        XCTAssertEqual(ledger.publishedCount, 3)
        XCTAssertEqual(ledger.count(.superseded), 2)
        XCTAssertEqual(ledger.count(.presented), 1)
        XCTAssertEqual(ledger.framesInFlightCount, 0)
        XCTAssertTrue(ledger.isBalanced)
    }

    func testAnUnaccountedEnqueueDoesNotMoveTheBooks() throws {
        // Spec 028. SwiftUI rebuilds the framebuffer view on any state change,
        // far more often than frames arrive, and those rebuilds re-enqueue the
        // same framebuffer. The first device export counted them: 568 published
        // against 11 content frames, which reads as a catastrophic presentation
        // failure when presentation was in fact keeping up exactly.
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        renderer.recordPublishedFrame()
        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 1, green: 0, blue: 0))
        )
        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 2, green: 0, blue: 0)),
            recordsSupersededOutcome: false
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let ledger = renderer.presentationLedger
        XCTAssertEqual(ledger.publishedCount, 1)
        XCTAssertEqual(ledger.count(.superseded), 0)
        XCTAssertEqual(ledger.count(.presented), 1)
        XCTAssertTrue(ledger.isBalanced)
    }

    func testAClearEventStartsTheBooksOverInsteadOfCarryingARemainder() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        renderer.recordPublishedFrame()
        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 10, green: 0, blue: 0))
        )
        renderer.clearFramebuffers()

        XCTAssertEqual(renderer.presentationLedger.publishedCount, 0)
        XCTAssertEqual(renderer.presentationLedger.terminalCount, 0)
        XCTAssertTrue(renderer.presentationLedger.isBalanced)
    }

    // MARK: - Dirty-rect partial uploads

    func testFullUploadCountsAsSingleRegion() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        renderer.enqueue(
            RFBRawFramebuffer(width: 8, height: 4, fill: RFBColor(red: 5, green: 5, blue: 5))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(
            renderer.lastUploadRegionCount,
            1,
            "A nil/empty dirty-rect list must perform exactly one full-frame upload."
        )
    }

    func testSuccessfulUploadReportsTimingSample() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        var samples: [Int] = []
        renderer.uploadTimingHandler = { milliseconds in
            samples.append(milliseconds)
        }

        renderer.enqueue(
            RFBRawFramebuffer(width: 8, height: 4, fill: RFBColor(red: 5, green: 5, blue: 5))
        )

        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(renderer.lastUploadMilliseconds, samples.first)
        XCTAssertGreaterThanOrEqual(samples[0], 0)
    }

    func testTwoNonOverlappingDirtyRectsIssueTwoPartialUploads() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        // Initial full upload to lock in the texture dimensions.
        let baseline = RFBRawFramebuffer(
            width: 16,
            height: 8,
            fill: RFBColor(red: 0, green: 0, blue: 0, alpha: 255)
        )
        renderer.enqueue(baseline)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(renderer.lastUploadRegionCount, 1)

        // Same dimensions + two non-overlapping rects.  The renderer
        // must take the partial-upload path and issue exactly two
        // `replaceRegion` calls — one per rect.
        let next = RFBRawFramebuffer(
            width: 16,
            height: 8,
            fill: RFBColor(red: 200, green: 50, blue: 25, alpha: 255)
        )
        renderer.enqueue(
            next,
            dirtyRectangles: [
                RFBFrameDamageRect(x: 0, y: 0, width: 4, height: 2),
                RFBFrameDamageRect(x: 8, y: 4, width: 4, height: 2)
            ]
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(
            renderer.lastUploadRegionCount,
            2,
            "Each non-overlapping in-bounds dirty rect must produce one partial upload."
        )
    }

    func testOutOfBoundsDirtyRectsAreSkippedWithoutCrashing() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        // Lock the texture to 8×8 first.
        renderer.enqueue(
            RFBRawFramebuffer(width: 8, height: 8, fill: RFBColor(red: 0, green: 0, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        // Three rects: two out of bounds, one valid.  Out-of-bounds
        // rects must be ignored silently — the in-bounds rect must
        // still upload, so the count is exactly one.
        let updated = RFBRawFramebuffer(
            width: 8,
            height: 8,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        renderer.enqueue(
            updated,
            dirtyRectangles: [
                RFBFrameDamageRect(x: 6, y: 0, width: 4, height: 2),   // x+w > width
                RFBFrameDamageRect(x: 0, y: 7, width: 2, height: 4),   // y+h > height
                RFBFrameDamageRect(x: 1, y: 1, width: 2, height: 2)    // valid
            ]
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(
            renderer.lastUploadRegionCount,
            1,
            "Out-of-bounds rects must be skipped, leaving the single valid rect uploaded."
        )
    }

    func testPartialUploadPreservesUntouchedPixelsFromPreviousFrame() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        // Establish a fully-filled red baseline texture.
        let baseline = RFBRawFramebuffer(
            width: 4,
            height: 2,
            fill: RFBColor(red: 200, green: 0, blue: 0, alpha: 255)
        )
        renderer.enqueue(baseline)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        // Heterogeneous "next" buffer: green inside the dirty rect,
        // blue elsewhere.  The partial upload should copy ONLY the
        // green region — the right half and bottom row of the texture
        // must remain the baseline red, NOT blue.  That is the
        // assertion that proves the dirty-rect path actually skipped
        // the rest of the buffer.
        let dirtyRect = RFBFrameDamageRect(x: 0, y: 0, width: 2, height: 1)
        let heterogeneousNext = try makeHeterogeneousFramebuffer(
            width: 4,
            height: 2,
            dirtyColor: RFBColor(red: 0, green: 220, blue: 0, alpha: 255),
            otherColor: RFBColor(red: 0, green: 0, blue: 222, alpha: 255),
            dirtyRect: dirtyRect
        )

        renderer.enqueue(
            heterogeneousNext,
            dirtyRectangles: [dirtyRect]
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(renderer.lastUploadRegionCount, 1)

        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        // RGBA8Unorm; row 0 has 4 pixels = 16 bytes.
        // Pixel (0,0) — green from dirty rect.
        XCTAssertEqual(bytes[0], 0)
        XCTAssertEqual(bytes[1], 220)
        XCTAssertEqual(bytes[2], 0)
        // Pixel (2,0) — outside the dirty rect, must still be red
        // from the baseline (NOT blue from the heterogeneous next
        // buffer).
        XCTAssertEqual(bytes[8], 200, "untouched pixel must keep baseline red")
        XCTAssertEqual(bytes[9], 0)
        XCTAssertEqual(bytes[10], 0)
        // Pixel (0,1) — bottom row, also outside the dirty rect.
        XCTAssertEqual(bytes[16], 200, "untouched bottom-row pixel keeps baseline red")
        XCTAssertEqual(bytes[17], 0)
        XCTAssertEqual(bytes[18], 0)
    }

    func testStagedPreparationUsesFullBufferWhenTextureIsMissing() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        let dirtyRect = RFBFrameDamageRect(x: 0, y: 0, width: 4, height: 2)
        let framebuffer = RFBRawFramebuffer(
            width: 16,
            height: 8,
            fill: RFBColor(red: 0, green: 220, blue: 0, alpha: 255)
        )

        let byteCount = try XCTUnwrap(
            renderer.stagedUploadByteCountForTesting(
                framebuffer: framebuffer,
                dirtyRectangles: [dirtyRect],
                changedPixelCount: dirtyRect.width * dirtyRect.height
            )
        )

        XCTAssertEqual(
            byteCount,
            16 * 8 * 4,
            "First-frame or dimension-changing staged uploads must keep a full buffer."
        )
    }

    func testStagedSmallDirtyRectPreparationUsesPartialBufferWhenTextureMatches() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))
        renderer.enqueue(
            RFBRawFramebuffer(width: 16, height: 8, fill: RFBColor(red: 200, green: 0, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let dirtyRect = RFBFrameDamageRect(x: 2, y: 1, width: 4, height: 2)
        let framebuffer = RFBRawFramebuffer(
            width: 16,
            height: 8,
            fill: RFBColor(red: 0, green: 220, blue: 0, alpha: 255)
        )
        let byteCount = try XCTUnwrap(
            renderer.stagedUploadByteCountForTesting(
                framebuffer: framebuffer,
                dirtyRectangles: [dirtyRect],
                changedPixelCount: dirtyRect.width * dirtyRect.height
            )
        )

        XCTAssertEqual(
            byteCount,
            dirtyRect.width * dirtyRect.height * 4,
            "Steady-state staged uploads should copy only the dirty rect bytes."
        )
    }

    func testPreparedStagedPartialUploadPreservesUntouchedPixelsFromPreviousFrame() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        let baseline = RFBRawFramebuffer(
            width: 4,
            height: 2,
            fill: RFBColor(red: 200, green: 0, blue: 0, alpha: 255)
        )
        renderer.enqueue(baseline)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        let dirtyRect = RFBFrameDamageRect(x: 0, y: 0, width: 2, height: 1)
        let next = try makeHeterogeneousFramebuffer(
            width: 4,
            height: 2,
            dirtyColor: RFBColor(red: 0, green: 220, blue: 0, alpha: 255),
            otherColor: RFBColor(red: 0, green: 0, blue: 222, alpha: 255),
            dirtyRect: dirtyRect
        )

        XCTAssertTrue(
            renderer.preparePendingStagedUploadForTesting(
                framebuffer: next,
                dirtyRectangles: [dirtyRect],
                changedPixelCount: dirtyRect.width * dirtyRect.height
            )
        )
        XCTAssertTrue(renderer.applyPendingStagedUploadForTesting())
        XCTAssertEqual(renderer.lastUploadRegionCount, 1)

        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        XCTAssertEqual(bytes[0], 0)
        XCTAssertEqual(bytes[1], 220)
        XCTAssertEqual(bytes[2], 0)
        XCTAssertEqual(bytes[8], 200, "untouched pixel must keep baseline red")
        XCTAssertEqual(bytes[9], 0)
        XCTAssertEqual(bytes[10], 0)
        XCTAssertEqual(bytes[16], 200, "untouched bottom-row pixel keeps baseline red")
        XCTAssertEqual(bytes[17], 0)
        XCTAssertEqual(bytes[18], 0)
    }

    func testLargeDirtyAreaFallsBackToFullUpload() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        let baseline = RFBRawFramebuffer(
            width: 4,
            height: 4,
            fill: RFBColor(red: 200, green: 0, blue: 0, alpha: 255)
        )
        renderer.enqueue(baseline)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        // 12/16 pixels changed (75%). That is above the renderer's
        // partial-upload area ceiling, so it should choose one full
        // upload. The heterogeneous buffer lets us distinguish full
        // upload from a single large partial upload: pixels outside the
        // dirty rect become blue only if the full buffer was copied.
        let dirtyRect = RFBFrameDamageRect(x: 0, y: 0, width: 4, height: 3)
        let next = try makeHeterogeneousFramebuffer(
            width: 4,
            height: 4,
            dirtyColor: RFBColor(red: 0, green: 220, blue: 0, alpha: 255),
            otherColor: RFBColor(red: 0, green: 0, blue: 222, alpha: 255),
            dirtyRect: dirtyRect
        )

        renderer.enqueue(next, dirtyRectangles: [dirtyRect])
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(renderer.lastUploadRegionCount, 1)

        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        let outsideDirtyRectOffset = ((3 * 4) + 0) * 4
        XCTAssertEqual(bytes[outsideDirtyRectOffset + 0], 0)
        XCTAssertEqual(bytes[outsideDirtyRectOffset + 1], 0)
        XCTAssertEqual(bytes[outsideDirtyRectOffset + 2], 222)
    }

    func testSparseLargeDirtyAreaUsesPartialUploadWhenChangedPixelCountIsLow() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        let baseline = RFBRawFramebuffer(
            width: 4,
            height: 4,
            fill: RFBColor(red: 200, green: 0, blue: 0, alpha: 255)
        )
        renderer.enqueue(baseline)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        // 12/16 pixels are in the dirty rect (75%), but the decoder
        // counted only one changed pixel inside that server damage
        // region. Uploading that rect is still cheaper than copying the
        // whole texture, and pixels outside the dirty rect must remain
        // the prior baseline color.
        let dirtyRect = RFBFrameDamageRect(x: 0, y: 0, width: 4, height: 3)
        let next = try makeHeterogeneousFramebuffer(
            width: 4,
            height: 4,
            dirtyColor: RFBColor(red: 0, green: 220, blue: 0, alpha: 255),
            otherColor: RFBColor(red: 0, green: 0, blue: 222, alpha: 255),
            dirtyRect: dirtyRect
        )

        renderer.enqueue(next, dirtyRectangles: [dirtyRect], changedPixelCount: 1)
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(renderer.lastUploadRegionCount, 1)

        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        let outsideDirtyRectOffset = ((3 * 4) + 0) * 4
        XCTAssertEqual(bytes[outsideDirtyRectOffset + 0], 200)
        XCTAssertEqual(bytes[outsideDirtyRectOffset + 1], 0)
        XCTAssertEqual(bytes[outsideDirtyRectOffset + 2], 0)
    }

    /// Contract changed 2026-08-21 (spec 024). This case used to assert that
    /// more rectangles than the partial cap re-uploads the entire texture; that
    /// is exactly what live measurement showed re-uploading every pixel for
    /// frames whose damage was under 1% of the framebuffer. The rectangles are
    /// merged now, and the renderer must upload the *merged* set — so damaged
    /// pixels refresh and undamaged ones are left alone, as on any other
    /// partial upload.
    func testTooManyDirtyRectsUploadMergedRegionsInsteadOfTheWholeTexture() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        renderer.enqueue(
            RFBRawFramebuffer(width: 16, height: 16, fill: RFBColor(red: 200, green: 0, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        // 65 single-pixel rectangles over rows 0...4 — one more than the cap,
        // and none of them touches the bottom-right corner.
        let tinyRects = (0...MetalFramebufferRenderer.maximumPartialUploadRegionCount).map { index in
            RFBFrameDamageRect(x: index % 16, y: index / 16, width: 1, height: 1)
        }
        renderer.enqueue(
            RFBRawFramebuffer(width: 16, height: 16, fill: RFBColor(red: 0, green: 0, blue: 222)),
            dirtyRectangles: tinyRects
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertGreaterThan(renderer.lastUploadRegionCount, 0)
        XCTAssertLessThanOrEqual(
            renderer.lastUploadRegionCount,
            MetalFramebufferRenderer.maximumPartialUploadRegionCount,
            "Merging must bring the region count back under the partial cap."
        )

        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        // Inside the damage: refreshed.
        let insideDamageOffset = ((0 * 16) + 0) * 4
        XCTAssertEqual(bytes[insideDamageOffset + 0], 0)
        XCTAssertEqual(bytes[insideDamageOffset + 2], 222)
        // Outside the damage: untouched, the same as any partial upload.
        let outsideTinyRectsOffset = ((15 * 16) + 15) * 4
        XCTAssertEqual(bytes[outsideTinyRectsOffset + 0], 200)
        XCTAssertEqual(bytes[outsideTinyRectsOffset + 2], 0)
    }

    func testFirstFrameAfterDimensionChangeForcesFullUpload() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        // Lock a 4×4 baseline texture.
        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 0, green: 0, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(renderer.lastUploadRegionCount, 1)

        // Enqueue a different-dimension buffer with non-empty dirty
        // rects.  The renderer is expected to recreate the texture
        // and perform a single full-frame upload — partial uploads
        // would leave the rest of the freshly allocated 8×2 texture
        // uninitialized.
        let resized = RFBRawFramebuffer(
            width: 8,
            height: 2,
            fill: RFBColor(red: 50, green: 100, blue: 150, alpha: 255)
        )
        renderer.enqueue(
            resized,
            dirtyRectangles: [
                RFBFrameDamageRect(x: 0, y: 0, width: 4, height: 1),
                RFBFrameDamageRect(x: 4, y: 1, width: 4, height: 1)
            ]
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(
            renderer.lastUploadRegionCount,
            1,
            "A dimension change must force a single full-frame upload regardless of dirty rects."
        )

        let size = try XCTUnwrap(renderer.currentTextureSize)
        XCTAssertEqual(size.width, 8)
        XCTAssertEqual(size.height, 2)

        // Every byte of the readback must reflect the new fill, with
        // no residue from the prior 4×4 black texture.
        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        XCTAssertEqual(bytes.count, 8 * 2 * 4)
        for pixelIndex in 0..<(8 * 2) {
            XCTAssertEqual(bytes[pixelIndex * 4 + 0], 50, "red @ pixel \(pixelIndex)")
            XCTAssertEqual(bytes[pixelIndex * 4 + 1], 100, "green @ pixel \(pixelIndex)")
            XCTAssertEqual(bytes[pixelIndex * 4 + 2], 150, "blue @ pixel \(pixelIndex)")
        }
    }

    func testEmptyDirtyRectListUploadsFullFrame() throws {
        let device = try requireDevice()
        let renderer = try XCTUnwrap(MetalFramebufferRenderer(device: device))

        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 0, green: 0, blue: 0))
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())

        // Empty dirty-rect list — semantically "no recorded damage".
        // The renderer must still take the safe full-upload path
        // rather than skip the upload entirely; otherwise a stale
        // texture would survive on screen.
        renderer.enqueue(
            RFBRawFramebuffer(width: 4, height: 4, fill: RFBColor(red: 90, green: 90, blue: 90)),
            dirtyRectangles: []
        )
        XCTAssertTrue(renderer.uploadPendingFramebufferForTesting())
        XCTAssertEqual(
            renderer.lastUploadRegionCount,
            1,
            "Empty rect list falls through to the full-frame path."
        )

        let bytes = try XCTUnwrap(renderer.readbackTextureForTesting())
        XCTAssertEqual(bytes[0], 90)
        XCTAssertEqual(bytes[1], 90)
        XCTAssertEqual(bytes[2], 90)
    }

    // MARK: - Helpers

    /// Builds a framebuffer where pixels inside `dirtyRect` get
    /// `dirtyColor` and every other pixel gets `otherColor`.  We
    /// build the buffer by round-tripping through `Codable` because
    /// `RFBRawFramebuffer.set(...)` is fileprivate inside
    /// `NaruRemoteCore` — Codable is the public mutation surface
    /// available to a black-box consumer like this test target.
    private func makeHeterogeneousFramebuffer(
        width: Int,
        height: Int,
        dirtyColor: RFBColor,
        otherColor: RFBColor,
        dirtyRect: RFBFrameDamageRect
    ) throws -> RFBRawFramebuffer {
        var pixels: [RFBColor] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let inside = x >= dirtyRect.x
                    && x < dirtyRect.x + dirtyRect.width
                    && y >= dirtyRect.y
                    && y < dirtyRect.y + dirtyRect.height
                pixels.append(inside ? dirtyColor : otherColor)
            }
        }
        struct FramebufferEncoded: Codable {
            let width: Int
            let height: Int
            let pixels: [RFBColor]
        }
        let payload = FramebufferEncoded(width: width, height: height, pixels: pixels)
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(RFBRawFramebuffer.self, from: data)
    }

    // MARK: - Aspect-fit viewport

    func testAspectFitCenteredHorizontalLetterboxing() {
        // 16:9 drawable, 1:1 texture — texture should fit on the
        // shorter axis (height) and be centered horizontally.
        let viewport = MetalFramebufferRenderer.aspectFitViewport(
            drawableSize: CGSize(width: 1600, height: 900),
            textureWidth: 100,
            textureHeight: 100
        )
        XCTAssertEqual(viewport.width, 900, accuracy: 0.001)
        XCTAssertEqual(viewport.height, 900, accuracy: 0.001)
        XCTAssertEqual(viewport.originX, 350, accuracy: 0.001)
        XCTAssertEqual(viewport.originY, 0, accuracy: 0.001)
    }

    func testAspectFitCenteredVerticalLetterboxing() {
        // 1:1 drawable, 4:3 texture — texture is wider than the
        // drawable per unit height, so it fits on width and is
        // centered vertically.
        let viewport = MetalFramebufferRenderer.aspectFitViewport(
            drawableSize: CGSize(width: 1000, height: 1000),
            textureWidth: 4,
            textureHeight: 3
        )
        XCTAssertEqual(viewport.width, 1000, accuracy: 0.001)
        XCTAssertEqual(viewport.height, 750, accuracy: 0.001)
        XCTAssertEqual(viewport.originX, 0, accuracy: 0.001)
        XCTAssertEqual(viewport.originY, 125, accuracy: 0.001)
    }

    func testAspectFitClampsToZeroForEmptyDrawable() {
        let viewport = MetalFramebufferRenderer.aspectFitViewport(
            drawableSize: .zero,
            textureWidth: 100,
            textureHeight: 100
        )
        XCTAssertEqual(viewport.width, 0)
        XCTAssertEqual(viewport.height, 0)
    }

    func testTransformedViewportMatchesAspectFitAtIdentity() {
        let viewport = MetalFramebufferRenderer.transformedViewport(
            drawableSize: CGSize(width: 1200, height: 900),
            viewSize: CGSize(width: 400, height: 300),
            textureWidth: 1600,
            textureHeight: 900,
            zoomScale: 1,
            panOffset: .zero
        )
        let aspectFit = MetalFramebufferRenderer.aspectFitViewport(
            drawableSize: CGSize(width: 1200, height: 900),
            textureWidth: 1600,
            textureHeight: 900
        )

        XCTAssertEqual(viewport.originX, aspectFit.originX, accuracy: 0.001)
        XCTAssertEqual(viewport.originY, aspectFit.originY, accuracy: 0.001)
        XCTAssertEqual(viewport.width, aspectFit.width, accuracy: 0.001)
        XCTAssertEqual(viewport.height, aspectFit.height, accuracy: 0.001)
    }

    func testTransformedViewportScalesAndPansInDrawablePixels() {
        let viewport = MetalFramebufferRenderer.transformedViewport(
            drawableSize: CGSize(width: 1200, height: 900),
            viewSize: CGSize(width: 400, height: 300),
            textureWidth: 200,
            textureHeight: 100,
            zoomScale: 2,
            panOffset: CGSize(width: 40, height: -20)
        )

        XCTAssertEqual(viewport.originX, -480, accuracy: 0.001)
        XCTAssertEqual(viewport.originY, -210, accuracy: 0.001)
        XCTAssertEqual(viewport.width, 2400, accuracy: 0.001)
        XCTAssertEqual(viewport.height, 1200, accuracy: 0.001)
    }
}
#endif
