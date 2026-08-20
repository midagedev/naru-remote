import CoreGraphics
import XCTest
@testable import NaruRemoteCore

final class AppleServerDownscalePolicyTests: XCTestCase {
    func testGateOffNeverFiresEvenAfterSustainedLosslessFit() {
        var policy = AppleServerDownscalePolicy()
        let transform = Self.exactLosslessUnzoomedTransform

        for _ in 0..<20 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: transform,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: false,
                    currentAppliedRung: AppleServerDownscalePolicy.fullRung
                )
            )
        }
    }

    func testNilTransformHolds() {
        var policy = AppleServerDownscalePolicy()

        XCTAssertNil(
            policy.requestedRung(
                transform: nil,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            )
        )
    }

    func testLosslessBoundaryEqualsHalfIsEligible() {
        var policy = AppleServerDownscalePolicy(eligibleTickThreshold: 1)
        let transform = Self.exactLosslessUnzoomedTransform

        XCTAssertEqual(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            ),
            AppleServerDownscalePolicy.downscaledRung
        )
    }

    func testLosslessBoundarySlightlyAboveHalfIsNotEligible() {
        var policy = AppleServerDownscalePolicy(eligibleTickThreshold: 1)
        let transform = Self.exactLosslessUnzoomedTransform

        XCTAssertNil(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1.0000001,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            )
        )
        // Rewritten 2026-08-20 with the rung-normalization fix (see
        // testStaysDownscaledAfterServerResizeAppliesTheHalfFramebuffer):
        // the original expectation (immediate 1.0) encoded the raw
        // re-evaluation that caused the 0.5↔1.0 flap. Under the invariant
        // `displayScale × appliedRung × ppp ≤ 0.5`, a full-size transform
        // seen while 0.5 is applied is the lazy pre-resize window — the
        // policy holds; the restore decision belongs to the tick where the
        // scaled transform arrives (asserted below).
        XCTAssertNil(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1.0000001,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.downscaledRung
            )
        )
        // Once the server's resize lands (transform now describes the
        // half framebuffer, displayScale doubled), the same
        // slightly-above-boundary geometry normalizes to just over 0.5
        // and restores full scale — exactly once, no flap.
        let scaledTransform = ViewportTransform(
            framebufferSize: CGSize(width: 500, height: 500),
            viewSize: CGSize(width: 500, height: 500)
        )
        XCTAssertEqual(
            policy.requestedRung(
                transform: scaledTransform,
                liveFramebufferWidth: 500,
                liveFramebufferHeight: 500,
                displayPixelsPerPoint: 1.0000001,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.downscaledRung
            ),
            AppleServerDownscalePolicy.fullRung
        )
    }

    func testAssumedPixelsPerPointThreeLosslessFit() {
        var policy = AppleServerDownscalePolicy(eligibleTickThreshold: 1)
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: 120, height: 120),
            viewSize: CGSize(width: 20, height: 20)
        )

        XCTAssertEqual(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 120,
                liveFramebufferHeight: 120,
                displayPixelsPerPoint: nil,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            ),
            AppleServerDownscalePolicy.downscaledRung
        )
    }

    func testNineEligibleTicksReturnNilTenthReturnsDownscale() {
        var policy = AppleServerDownscalePolicy()
        let transform = Self.exactLosslessUnzoomedTransform

        for tick in 1...9 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: transform,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.fullRung
                ),
                "tick \(tick) must still be inside hysteresis"
            )
        }

        XCTAssertEqual(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            ),
            AppleServerDownscalePolicy.downscaledRung
        )
    }

    func testDoesNotRepeatDownscaleRungWhileStillApplied() {
        var policy = AppleServerDownscalePolicy()
        let transform = Self.exactLosslessUnzoomedTransform

        for _ in 0..<10 {
            _ = policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            )
        }

        for _ in 0..<5 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: transform,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.downscaledRung
                )
            )
        }
    }

    func testZoomedRequestsFullScaleImmediatelyWhenDownscaled() {
        var policy = AppleServerDownscalePolicy()
        let zoomed = ViewportTransform(
            framebufferSize: CGSize(width: 1_000, height: 1_000),
            viewSize: CGSize(width: 500, height: 500),
            zoomScale: 2
        )

        XCTAssertEqual(
            policy.requestedRung(
                transform: zoomed,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.downscaledRung
            ),
            AppleServerDownscalePolicy.fullRung
        )
    }

    func testZoomedDoesNotResendFullScaleWhenAlreadyApplied() {
        var policy = AppleServerDownscalePolicy()
        let zoomed = ViewportTransform(
            framebufferSize: CGSize(width: 1_000, height: 1_000),
            viewSize: CGSize(width: 500, height: 500),
            zoomScale: 2
        )

        XCTAssertNil(
            policy.requestedRung(
                transform: zoomed,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            )
        )
    }

    func testZoomResetsEligibleCounter() {
        var policy = AppleServerDownscalePolicy()
        let fit = Self.exactLosslessUnzoomedTransform
        let zoomed = ViewportTransform(
            framebufferSize: CGSize(width: 1_000, height: 1_000),
            viewSize: CGSize(width: 500, height: 500),
            zoomScale: 2
        )

        for _ in 0..<9 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: fit,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.fullRung
                )
            )
        }

        XCTAssertNil(
            policy.requestedRung(
                transform: zoomed,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            )
        )

        for _ in 0..<9 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: fit,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.fullRung
                )
            )
        }
        XCTAssertEqual(
            policy.requestedRung(
                transform: fit,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            ),
            AppleServerDownscalePolicy.downscaledRung
        )
    }

    func testMidResizeHoldResetsCounter() {
        var policy = AppleServerDownscalePolicy()
        let transform = Self.exactLosslessUnzoomedTransform

        for _ in 0..<9 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: transform,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.fullRung
                )
            )
        }

        XCTAssertNil(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 2_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            )
        )

        for _ in 0..<9 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: transform,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.fullRung
                )
            )
        }
        XCTAssertEqual(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            ),
            AppleServerDownscalePolicy.downscaledRung
        )
    }

    func testMidResizeHeightMismatchAlsoHolds() {
        var policy = AppleServerDownscalePolicy(eligibleTickThreshold: 1)
        let transform = Self.exactLosslessUnzoomedTransform

        XCTAssertNil(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 999,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            )
        )
    }

    func testUnzoomedDenseViewRestoresFullScale() {
        var policy = AppleServerDownscalePolicy(eligibleTickThreshold: 1)
        let dense = ViewportTransform(
            framebufferSize: CGSize(width: 1_000, height: 1_000),
            viewSize: CGSize(width: 500, height: 500)
        )

        XCTAssertEqual(
            policy.requestedRung(
                transform: dense,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 3,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.downscaledRung
            ),
            AppleServerDownscalePolicy.fullRung
        )
        XCTAssertNil(
            policy.requestedRung(
                transform: dense,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 3,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            )
        )
    }

    /// Spec-defect regression (2026-08-20, lead-authored spec bug found in
    /// review): once the server applies 0.5, DesktopSize halves the
    /// framebuffer and the published transform's `displayScale` doubles.
    /// Re-testing the raw lossless condition against that scaled transform
    /// reads "not lossless" and requests 1.0 — a 0.5↔1.0 flap loop every
    /// hysteresis window. The condition must be normalized by the applied
    /// rung (evaluate against the unscaled framebuffer). Geometry here:
    /// entry was lossless (full fb 3000px, view 400pt, ppp 3 → 0.4 ≤ 0.5);
    /// after the resize the scaled transform is fb 1500, displayScale
    /// 0.2667 → raw 0.8 fails, normalized 0.4 holds.
    func testStaysDownscaledAfterServerResizeAppliesTheHalfFramebuffer() {
        var policy = AppleServerDownscalePolicy(eligibleTickThreshold: 1)
        let scaledTransform = ViewportTransform(
            framebufferSize: CGSize(width: 1_500, height: 900),
            viewSize: CGSize(width: 400, height: 240)
        )

        for _ in 0..<5 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: scaledTransform,
                    liveFramebufferWidth: 1_500,
                    liveFramebufferHeight: 900,
                    displayPixelsPerPoint: 3,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.downscaledRung
                ),
                "A stably applied 0.5 rung must not flap back to 1.0 just because the transform now describes the half-size framebuffer"
            )
        }
    }

    // MARK: - Pointer coordinate mapping (input space stays unscaled)

    func testPointerMappingAdoptsFirstSeenWidthAsUnscaledTruth() {
        let mapping = AppleServerDownscalePolicy.pointerCoordinateMapping(
            knownUnscaledWidth: nil,
            currentWidth: 3_456
        )
        XCTAssertEqual(mapping.multiplier, 1)
        XCTAssertEqual(mapping.unscaledWidthToStore, 3_456)
    }

    func testPointerMappingDoublesCoordinatesForTheHalfShape() {
        for current in [1_728, 1_727, 1_729] {
            let mapping = AppleServerDownscalePolicy.pointerCoordinateMapping(
                knownUnscaledWidth: 3_456,
                currentWidth: current
            )
            XCTAssertEqual(
                mapping.multiplier,
                3_456.0 / Double(current),
                accuracy: 0.001,
                "half-shape width \(current) must map back to the unscaled space"
            )
            XCTAssertEqual(mapping.unscaledWidthToStore, 3_456)
        }
    }

    func testPointerMappingAdoptsRestoreAndResolutionChanges() {
        // Restore landed: current == known → adopt, multiplier 1.
        let restored = AppleServerDownscalePolicy.pointerCoordinateMapping(
            knownUnscaledWidth: 3_456,
            currentWidth: 3_456
        )
        XCTAssertEqual(restored.multiplier, 1)
        XCTAssertEqual(restored.unscaledWidthToStore, 3_456)

        // Genuine resolution change while un-scaled: not the half shape →
        // adopt the new width instead of inventing a multiplier.
        let resized = AppleServerDownscalePolicy.pointerCoordinateMapping(
            knownUnscaledWidth: 3_456,
            currentWidth: 2_560
        )
        XCTAssertEqual(resized.multiplier, 1)
        XCTAssertEqual(resized.unscaledWidthToStore, 2_560)
    }

    func testMappedPointerCommandScalesAndClamps() {
        let mapped = AppleServerDownscalePolicy.mappedPointerCommand(
            RFBPointerCommand(buttonMask: 1, x: 30, y: 45),
            multiplier: 2
        )
        XCTAssertEqual(mapped, RFBPointerCommand(buttonMask: 1, x: 60, y: 90))

        let clamped = AppleServerDownscalePolicy.mappedPointerCommand(
            RFBPointerCommand(buttonMask: 0, x: 60_000, y: 2),
            multiplier: 2
        )
        XCTAssertEqual(clamped.x, UInt16.max)
        XCTAssertEqual(clamped.y, 4)
    }

    func testResetClearsEligibleCounter() {
        var policy = AppleServerDownscalePolicy()
        let transform = Self.exactLosslessUnzoomedTransform

        for _ in 0..<9 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: transform,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.fullRung
                )
            )
        }

        policy.reset()

        for _ in 0..<9 {
            XCTAssertNil(
                policy.requestedRung(
                    transform: transform,
                    liveFramebufferWidth: 1_000,
                    liveFramebufferHeight: 1_000,
                    displayPixelsPerPoint: 1,
                    serverAdvertisedAppleSecurity: true,
                    currentAppliedRung: AppleServerDownscalePolicy.fullRung
                )
            )
        }
        XCTAssertEqual(
            policy.requestedRung(
                transform: transform,
                liveFramebufferWidth: 1_000,
                liveFramebufferHeight: 1_000,
                displayPixelsPerPoint: 1,
                serverAdvertisedAppleSecurity: true,
                currentAppliedRung: AppleServerDownscalePolicy.fullRung
            ),
            AppleServerDownscalePolicy.downscaledRung
        )
    }

    /// 1000×1000 fit into 500×500 → displayScale 0.5 exactly. With
    /// displayPixelsPerPoint 1, displayScale·ppp == 0.5 (lossless boundary).
    private static let exactLosslessUnzoomedTransform = ViewportTransform(
        framebufferSize: CGSize(width: 1_000, height: 1_000),
        viewSize: CGSize(width: 500, height: 500)
    )
}
