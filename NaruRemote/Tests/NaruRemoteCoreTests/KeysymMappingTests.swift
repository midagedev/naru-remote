import XCTest
@testable import NaruRemoteCore

final class KeysymMappingTests: XCTestCase {

    // MARK: - Printable ASCII

    func testPrintableAsciiCharacterMapsToIdenticalKeysym() {
        // X11 keysym values for printable ASCII (0x20-0x7E) are
        // identical to the ASCII code itself.
        XCTAssertEqual(KeysymMapping.keysym(for: " "), 0x20)
        XCTAssertEqual(KeysymMapping.keysym(for: "0"), 0x30)
        XCTAssertEqual(KeysymMapping.keysym(for: "A"), 0x41)
        XCTAssertEqual(KeysymMapping.keysym(for: "a"), 0x61)
        XCTAssertEqual(KeysymMapping.keysym(for: "c"), 0x63)
        XCTAssertEqual(KeysymMapping.keysym(for: "z"), 0x7A)
        XCTAssertEqual(KeysymMapping.keysym(for: "~"), 0x7E)
    }

    func testPrintableAsciiBoundariesMap() {
        // 0x20 (space) and 0x7E (~) are the two boundary points
        // — a regression that picks up control chars or non-ASCII
        // would surface as one of these failing.
        XCTAssertEqual(KeysymMapping.keysym(for: Character(UnicodeScalar(0x20)!)), 0x20)
        XCTAssertEqual(KeysymMapping.keysym(for: Character(UnicodeScalar(0x7E)!)), 0x7E)
    }

    func testControlCharactersReturnNil() {
        // Control chars below 0x20 are NOT represented on the
        // QWERTY page; if a Character somehow gets through, drop
        // it (FR-015 silent drop).
        XCTAssertNil(KeysymMapping.keysym(for: Character(UnicodeScalar(0x01)!)))
        XCTAssertNil(KeysymMapping.keysym(for: Character(UnicodeScalar(0x1F)!)))
    }

    func testHigherAsciiAndNonAsciiReturnNil() {
        // 0x7F (DEL) and beyond are not on the QWERTY page; CJK /
        // emoji belong to Compose & Send (constitution §I).
        XCTAssertNil(KeysymMapping.keysym(for: Character(UnicodeScalar(0x7F)!)))
        XCTAssertNil(KeysymMapping.keysym(for: "한"))
        XCTAssertNil(KeysymMapping.keysym(for: "あ"))
        XCTAssertNil(KeysymMapping.keysym(for: "😊"))
        XCTAssertNil(KeysymMapping.keysym(for: "é"))
    }

    func testMultiScalarGraphemeReturnsNil() {
        // A Character with multiple unicode scalars (e.g., a
        // base + combining mark, or some emoji) cannot map to a
        // single keysym; return nil so the caller drops it.
        // "👨‍👩‍👧" is a multi-scalar grapheme cluster.
        let family: Character = "👨‍👩‍👧"
        XCTAssertNil(KeysymMapping.keysym(for: family))
    }

    // MARK: - NamedKey table

    func testNamedKeyValuesMatchX11Keysymdef() {
        // Locked values from research.md R-1 (X.Org keysymdef.h).
        XCTAssertEqual(KeysymMapping.keysym(for: .backspace),   0xFF08)
        XCTAssertEqual(KeysymMapping.keysym(for: .tab),         0xFF09)
        XCTAssertEqual(KeysymMapping.keysym(for: .return),      0xFF0D)
        XCTAssertEqual(KeysymMapping.keysym(for: .escape),      0xFF1B)
        XCTAssertEqual(KeysymMapping.keysym(for: .home),        0xFF50)
        XCTAssertEqual(KeysymMapping.keysym(for: .left),        0xFF51)
        XCTAssertEqual(KeysymMapping.keysym(for: .up),          0xFF52)
        XCTAssertEqual(KeysymMapping.keysym(for: .right),       0xFF53)
        XCTAssertEqual(KeysymMapping.keysym(for: .down),        0xFF54)
        XCTAssertEqual(KeysymMapping.keysym(for: .pageUp),      0xFF55)
        XCTAssertEqual(KeysymMapping.keysym(for: .pageDown),    0xFF56)
        XCTAssertEqual(KeysymMapping.keysym(for: .end),         0xFF57)
        XCTAssertEqual(KeysymMapping.keysym(for: .insert),      0xFF63)
        XCTAssertEqual(KeysymMapping.keysym(for: .delete),      0xFFFF)
        XCTAssertEqual(KeysymMapping.keysym(for: .shiftLeft),   0xFFE1)
        XCTAssertEqual(KeysymMapping.keysym(for: .controlLeft), 0xFFE3)
        XCTAssertEqual(KeysymMapping.keysym(for: .altLeft),     0xFFE9)
        XCTAssertEqual(KeysymMapping.keysym(for: .metaLeft),    0xFFE7)
    }

    func testFunctionKeysAreSequential() {
        // F1..F12 occupy 0xFFBE..0xFFC9 sequentially; a permuted
        // table would surface as a non-monotonic gap.
        XCTAssertEqual(KeysymMapping.keysym(for: .f1),  0xFFBE)
        XCTAssertEqual(KeysymMapping.keysym(for: .f2),  0xFFBF)
        XCTAssertEqual(KeysymMapping.keysym(for: .f3),  0xFFC0)
        XCTAssertEqual(KeysymMapping.keysym(for: .f4),  0xFFC1)
        XCTAssertEqual(KeysymMapping.keysym(for: .f5),  0xFFC2)
        XCTAssertEqual(KeysymMapping.keysym(for: .f6),  0xFFC3)
        XCTAssertEqual(KeysymMapping.keysym(for: .f7),  0xFFC4)
        XCTAssertEqual(KeysymMapping.keysym(for: .f8),  0xFFC5)
        XCTAssertEqual(KeysymMapping.keysym(for: .f9),  0xFFC6)
        XCTAssertEqual(KeysymMapping.keysym(for: .f10), 0xFFC7)
        XCTAssertEqual(KeysymMapping.keysym(for: .f11), 0xFFC8)
        XCTAssertEqual(KeysymMapping.keysym(for: .f12), 0xFFC9)
    }

    func testEveryNamedKeyHasNonZeroKeysym() {
        // Total surface — every NamedKey.allCases entry has a
        // keysym by construction.  A future case without a
        // mapping would surface as a 0 here (the switch's
        // exhaustiveness check would also catch it at compile
        // time, but this test guards against an accidentally
        // assigned 0).
        for key in KeysymMapping.NamedKey.allCases {
            XCTAssertNotEqual(KeysymMapping.keysym(for: key), 0, "NamedKey.\(key) maps to 0")
        }
    }

    func testNamedKeysAreUnique() {
        // No two NamedKey values map to the same X11 keysym —
        // duplicate mappings would surface a copy-paste error in
        // the table.
        let allKeysyms = KeysymMapping.NamedKey.allCases.map { KeysymMapping.keysym(for: $0) }
        let uniqueKeysyms = Set(allKeysyms)
        XCTAssertEqual(allKeysyms.count, uniqueKeysyms.count, "duplicate keysyms in NamedKey table")
    }
}
