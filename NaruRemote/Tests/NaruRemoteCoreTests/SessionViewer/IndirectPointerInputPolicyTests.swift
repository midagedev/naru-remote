import XCTest
@testable import NaruRemoteCore

/// Spec 012 US1 — indirect pointer (mouse / hardware trackpad) policy.
/// Each test pins at least two contract assertions (FAIL-first).
final class IndirectPointerInputPolicyTests: XCTestCase {

    func testHoverRoutesBothModesToRemoteMove() {
        XCTAssertEqual(
            IndirectPointerInputPolicy.hoverRoute(for: .directTouch),
            .absoluteMove,
            "Direct-touch hover is an absolute remote pointer move."
        )
        XCTAssertEqual(
            IndirectPointerInputPolicy.hoverRoute(for: .trackpad),
            .trackpadRelative,
            "Trackpad hover keeps the existing hoverMoved resolver path."
        )
        XCTAssertNotEqual(
            IndirectPointerInputPolicy.HoverRoute.absoluteMove,
            IndirectPointerInputPolicy.HoverRoute.trackpadRelative,
            "The two modes differ only in absolute vs trackpad routing."
        )
    }

    func testSecondaryClickRoutesByMode() {
        XCTAssertEqual(
            IndirectPointerInputPolicy.secondaryClickRoute(for: .directTouch),
            .absoluteRightClick
        )
        XCTAssertEqual(
            IndirectPointerInputPolicy.secondaryClickRoute(for: .trackpad),
            .trackpadSecondaryTap
        )
    }

    func testScrollWheelRecognizerUsesZeroTouchesAndScrollMask() {
        XCTAssertEqual(IndirectPointerInputPolicy.scrollWheelMinimumNumberOfTouches, 0)
        XCTAssertEqual(IndirectPointerInputPolicy.scrollWheelMaximumNumberOfTouches, 0)
        XCTAssertTrue(IndirectPointerInputPolicy.scrollWheelRequiresScrollTypeMask)
        // UIScrollTypeMask.all = discrete (1<<0) | continuous (1<<1)
        XCTAssertEqual(
            IndirectPointerInputPolicy.scrollWheelAllowedScrollTypesMaskRawValue,
            (1 << 0) | (1 << 1)
        )
    }

    func testSecondaryButtonTapRequiresOneTouchAndSecondaryButton() {
        XCTAssertEqual(
            IndirectPointerInputPolicy.secondaryButtonTapNumberOfTouchesRequired,
            1
        )
        XCTAssertEqual(
            IndirectPointerInputPolicy.secondaryButtonTapRequiredButton,
            .secondary
        )
        XCTAssertEqual(
            IndirectPointerInputPolicy.secondaryButtonTapRequiredButton.rawValue,
            1 << 1
        )
    }

    func testPrimaryAndDoubleTapRequirePrimaryButton() {
        XCTAssertEqual(
            IndirectPointerInputPolicy.primaryTapRequiredButton,
            .primary
        )
        XCTAssertEqual(
            IndirectPointerInputPolicy.doubleTapRequiredButton,
            .primary
        )
        XCTAssertEqual(
            IndirectPointerInputPolicy.primaryTapRequiredButton.rawValue,
            1 << 0
        )
    }

    func testPencilHoverIsExcluded() {
        XCTAssertTrue(IndirectPointerInputPolicy.excludesPencilHover)
        // UITouch.TouchType.indirectPointer — not pencil (2) or direct (0).
        XCTAssertEqual(
            IndirectPointerInputPolicy.indirectPointerTouchTypeRawValue,
            3
        )
        XCTAssertNotEqual(
            IndirectPointerInputPolicy.indirectPointerTouchTypeRawValue,
            2,
            "Pencil/stylus must not be in the hover allowed-touch set."
        )
    }

    func testHidesSystemPointerOverSessionView() {
        XCTAssertTrue(IndirectPointerInputPolicy.hidesSystemPointerOverSessionView)
        XCTAssertTrue(
            IndirectPointerInputPolicy.excludesPencilHover,
            "Pointer hide and Pencil exclusion are independent US1-3/US1-4 gates."
        )
    }
}
