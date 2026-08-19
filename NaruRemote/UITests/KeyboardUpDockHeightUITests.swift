import XCTest

/// How much of the phone does the dock eat while the keyboard is up?
///
/// The founder's scenario is a sustained terminal session on an iPhone over
/// cellular (constitution §VI). With the software keyboard raised, everything
/// between the keyboard's top edge and the bottom of the remote screen is
/// chrome — it is subtracted from the only thing the user came for, which is
/// the remote pixels. That budget was never measured, so this suite measures
/// it and pins it.
///
/// The contract is stated as "how many rows of chrome ride above the
/// keyboard", because that is the thing a human sees and the thing a layout
/// regression changes. One row is the target.
@MainActor
final class KeyboardUpDockHeightUITests: XCTestCase {

    /// A row's controls are 40pt; with the surface's 8pt top and bottom
    /// padding a single-row dock spans ~56pt. 72pt leaves room for a taller
    /// control without admitting a second row (which costs ≥44pt more).
    /// Since v1.1 the Compose editor is one line tall too, so a single budget
    /// covers both modes.
    private static let singleRowSpanBudget: CGFloat = 72

    /// Spec 015 v1.1 FR-008: Type mode's row IS the soft-key strip — no text
    /// field, no `⋯` (there is nothing left to reveal), at every width. The
    /// mirror editor still exists at 1×1pt as the keyboard's first responder;
    /// visibly growing it would rebuild the field the founder asked removed.
    func testTypeModeIsOneRowOfSoftKeysWithNoTextField() throws {
        let app = launchLiveSession()
        try raiseKeyboard(in: app, via: "naru.input.type-reveal")

        XCTAssertTrue(
            app.descendants(matching: .any)["naru.input.accessory.strip"]
                .waitForExistence(timeout: 6),
            "Type mode's row is the strip; it must be on screen untapped"
        )
        XCTAssertFalse(
            app.buttons["naru.input.accessory.panel-toggle"].exists,
            "Type mode has no ⋯ — the strip is already its row"
        )
        let editor = app.descendants(matching: .any)["naru.input.editor"].firstMatch
        if editor.exists {
            XCTAssertLessThanOrEqual(
                editor.frame.height,
                1.5,
                "Type mode's mirror editor is a hidden first responder, not a visible field"
            )
            // Invisible must not mean dead: the 1×1 editor is what receives
            // the keystrokes, so it has to actually hold keyboard focus after
            // the reveal — a field that is hidden AND unfocused is a Type
            // mode that silently types nothing.
            let deadline = Date().addingTimeInterval(6)
            var editorHasFocus = false
            while Date() < deadline, !editorHasFocus {
                editorHasFocus = (editor.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
                if !editorHasFocus { usleep(250_000) }
            }
            XCTAssertTrue(
                editorHasFocus,
                "The hidden mirror editor must hold keyboard focus so Type mode still streams keystrokes"
            )
        }

        let measurement = try measureChrome(in: app, mode: "type")
        XCTAssertEqual(
            measurement.bands.count,
            1,
            """
            Type mode stacks \(measurement.bandDescription).
            Everything above the keyboard is taken from the remote screen; the \
            founder types into a terminal here, so this must be one row.
            """
        )
        XCTAssertLessThanOrEqual(
            measurement.span,
            Self.singleRowSpanBudget,
            "One row, but a tall one: \(measurement.description)"
        )
    }

    func testComposeModeKeepsItsChromeToOneRow() throws {
        let app = launchLiveSession()
        try raiseKeyboard(in: app, via: "naru.input.compose-reveal")
        try skipUnlessCompactDock(app, requirement: "FR-001's one-row budget")

        let measurement = try measureChrome(in: app, mode: "compose")
        XCTAssertEqual(
            measurement.bands.count,
            1,
            "Compose stacks \(measurement.bandDescription)."
        )
        XCTAssertLessThanOrEqual(
            measurement.span,
            Self.singleRowSpanBudget,
            "Compose's one-line row grew: \(measurement.description)"
        )
    }

    /// FR-005: at regular width the Compose panel is permanent, so there is
    /// nothing to reveal and no `⋯` to reveal it with. iPad has the height;
    /// the six rows this spec closes were an iPhone problem. (Type mode is
    /// the same single row at every width since v1.1, so the permanent-panel
    /// contract is Compose's.)
    func testRegularWidthKeepsTheKeysWithoutATap() throws {
        let app = launchLiveSession()
        try raiseKeyboard(in: app, via: "naru.input.compose-reveal")

        guard !app.buttons["naru.input.accessory.panel-toggle"].exists else {
            throw XCTSkip("Compact dock — FR-005 is about the regular-width dock")
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["naru.input.accessory.strip"]
                .waitForExistence(timeout: 6),
            "A regular-width dock keeps the accessory strip on screen untapped"
        )
        let measurement = try measureChrome(in: app, mode: "regular-width")
        XCTAssertEqual(
            measurement.bands.count,
            2,
            "Regular width is the row plus the permanent panel — no more: \(measurement.bandDescription)"
        )
    }

    /// The `⋯` panel is opt-in, so it is allowed to add a row — but exactly
    /// one, and only while it is open (FR-003). Since v1.1 the `⋯` lives on
    /// Compose's row only.
    func testRevealingTheKeyPanelAddsExactlyOneRow() throws {
        let app = launchLiveSession()
        try raiseKeyboard(in: app, via: "naru.input.compose-reveal")
        try skipUnlessCompactDock(app, requirement: "the ⋯ panel")
        let collapsed = try measureChrome(in: app, mode: "compose-collapsed")

        let toggle = app.buttons["naru.input.accessory.panel-toggle"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 4),
            "The keys have to be reachable: FR-002 puts a ⋯ on the row"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["naru.input.accessory.strip"].isHittable,
            "The panel starts collapsed (FR-004) — that is the founder's ask"
        )
        toggle.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["naru.input.accessory.strip"]
                .waitForExistence(timeout: 4),
            "One tap on ⋯ reveals the accessory strip"
        )
        let expanded = try measureChrome(in: app, mode: "compose-expanded")
        XCTAssertEqual(
            expanded.bands.count,
            collapsed.bands.count + 1,
            "Revealing the keys adds one row, not a stack: \(expanded.bandDescription)"
        )
    }

    // MARK: - Measurement

    /// The measurement is stated in **rows**, not points, for two reasons: it
    /// is what the user sees, and it does not depend on whether the simulator
    /// raised a software keyboard (a hardware keyboard suppresses it, and the
    /// dock then rests on the bottom safe area instead — the rows above are
    /// identical either way).
    ///
    /// A "row" is a band of vertically overlapping elements. Controls that
    /// share a row overlap; a control on its own row does not.
    private struct ChromeMeasurement {
        let bands: [[(String, CGRect)]]
        let chromeHeight: CGFloat
        let keyboardTop: CGFloat
        let chromeTop: CGFloat
        let rows: [(String, CGRect)]

        /// Top of the highest row to the bottom of the lowest — the chrome's
        /// own extent, excluding the safe-area gap below it.
        var span: CGFloat {
            guard let top = rows.map(\.1.minY).min(),
                  let bottom = rows.map(\.1.maxY).max()
            else { return 0 }
            return bottom - top
        }

        var bandDescription: String {
            bands
                .enumerated()
                .map { index, band in
                    let names = band.map(\.0).joined(separator: " + ")
                    let top = Int(band.map(\.1.minY).min() ?? 0)
                    let bottom = Int(band.map(\.1.maxY).max() ?? 0)
                    return "row \(index + 1) y=\(top)..\(bottom): \(names)"
                }
                .joined(separator: " | ")
        }

        var description: String {
            """
            \(bands.count) row(s), span \(Int(span))pt, \(Int(chromeHeight))pt to the \
            keyboard/window edge (y=\(Int(keyboardTop)), chrome top y=\(Int(chromeTop))). \
            \(bandDescription)
            """
        }
    }

    /// Every dock element that can ride above the keyboard. The measurement is
    /// the union of what is actually on screen, not a hard-coded row list, so
    /// a newly added row is caught instead of being silently excluded.
    private static let dockElementIdentifiers = [
        "naru.input.accessory.panel-toggle",
        "naru.input.accessory.strip",
        "naru.input.accessory.fn",
        "naru.input.accessory.fn-row",
        "naru.input.mode-toggle",
        "naru.input.keyboard-dismiss",
        "naru.input.mode-picker",
        "naru.input.mac-controls.menu",
        "naru.input.editor",
        "naru.input.send",
        "naru.input.compose-action.backspace",
        "naru.input.compose-action.enter",
        "naru.input.compose-reveal",
        "naru.input.compact-status",
        "naru.input.helper-status",
        "naru.input.focused-status",
        "naru.input.live-status",
        "naru.input.live-disclosure",
    ]

    private func measureChrome(in app: XCUIApplication, mode: String) throws -> ChromeMeasurement {
        let window = app.windows.firstMatch.frame
        // The reference line is whatever the dock sits on. A simulator with a
        // hardware keyboard attached raises no software keyboard, and the dock
        // then rests on the window's bottom edge — the row layout above it is
        // the same either way, so the measurement holds instead of skipping
        // (a skip here is what let the stack grow unwatched).
        let keyboard = app.keyboards.firstMatch
        let keyboardTop: CGFloat
        if keyboard.exists, keyboard.frame.height > 100, keyboard.frame.minY < window.maxY {
            keyboardTop = keyboard.frame.minY
        } else {
            keyboardTop = window.maxY
        }

        var rows: [(String, CGRect)] = []
        for identifier in Self.dockElementIdentifiers {
            let element = app.descendants(matching: .any)[identifier]
            guard element.exists else { continue }
            let frame = element.frame
            // Off-screen and zero-sized elements exist in the tree without
            // occupying the screen; only what is above the keyboard and
            // inside the window counts against the budget.
            guard frame.height > 1, frame.maxY <= keyboardTop + 1, frame.minY >= 0 else { continue }
            rows.append((identifier, frame))
        }

        let chromeTop = rows.map(\.1.minY).min() ?? keyboardTop
        let sorted = rows.sorted { $0.1.minY < $1.1.minY }
        let measurement = ChromeMeasurement(
            bands: Self.rowBands(of: sorted),
            chromeHeight: keyboardTop - chromeTop,
            keyboardTop: keyboardTop,
            chromeTop: chromeTop,
            rows: sorted
        )
        print("[dock-chrome:\(mode)] \(measurement.description)")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = "keyboard-up-\(mode).png"
        add(attachment)

        return measurement
    }

    /// Groups elements into rows: walking top-down, an element joins the
    /// current row while its top is above the row's current bottom (they
    /// overlap vertically), and starts a new row otherwise.
    private static func rowBands(of rows: [(String, CGRect)]) -> [[(String, CGRect)]] {
        var bands: [[(String, CGRect)]] = []
        var currentBottom: CGFloat = -.greatestFiniteMagnitude

        for row in rows {
            if row.1.minY < currentBottom - 1, var last = bands.popLast() {
                last.append(row)
                bands.append(last)
                currentBottom = max(currentBottom, row.1.maxY)
            } else {
                bands.append([row])
                currentBottom = row.1.maxY
            }
        }
        return bands
    }

    // MARK: - Helpers

    /// Which contract applies is decided by the app, not by guessing the
    /// device: the `⋯` toggle exists exactly when the panel is collapsible,
    /// i.e. at compact width (`RemoteInputDockView.panelIsPermanent`). Reading
    /// the window width instead would misjudge a Max-model iPhone in
    /// landscape, which is regular width.
    private func skipUnlessCompactDock(
        _ app: XCUIApplication,
        requirement: String
    ) throws {
        guard app.buttons["naru.input.accessory.panel-toggle"].waitForExistence(timeout: 6) else {
            throw XCTSkip("Regular-width dock keeps the panel permanently (FR-005) — \(requirement) is the compact contract")
        }
    }

    private func raiseKeyboard(in app: XCUIApplication, via identifier: String) throws {
        let reveal = app.buttons[identifier]
        guard reveal.waitForExistence(timeout: 8) else {
            throw XCTSkip("\(identifier) is not on screen; the live dock did not mount")
        }
        reveal.tap()

        // `exists` is true for a keyboard parked off-screen, so wait on
        // geometry: the keyboard has to actually intersect the window.
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.frame.intersects(window.frame), keyboard.frame.height > 100 {
                break
            }
            usleep(200_000)
        }
    }

    private func launchLiveSession() -> XCUIApplication {
        let app = XCUIApplication()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profiles.json")
        app.launchEnvironment["NARU_PROFILE_STORE_URL"] = storeURL.path
        app.launchEnvironment["NARU_TEST_FIXTURE_SNAPSHOT"] = "store-session-active"
        app.launchEnvironment["NARU_TEST_SUPPRESS_DIRECT_WARNING"] = "1"
        app.launch()
        return app
    }
}
