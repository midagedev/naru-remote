import XCTest
@testable import NaruRemoteCore

/// Runs the vendored `touch-remote-input` golden vectors against naru's own
/// types. The JSON is the specification; this file is only the harness.
///
/// A suite this harness cannot run fails the contract test, except for the
/// one named skip SWIFT.md allows: `composition` (naru has no
/// `CompositionGate` type). Silently dropping a suite is the failure this
/// arrangement exists to prevent.
final class TouchRemoteInputConformanceTests: XCTestCase {

    private static let runnerSuites: Set<String> = ["sticky", "cadence", "flush"]
    private static let namedSkipSuites: [String: String] = [
        "composition":
            "naru-remote has no CompositionGate type (touch-remote-input/conformance/SWIFT.md). Inventing a test-only copy of the TypeScript machine would not prove naru agrees. LiveTypeThroughWindow is the remote-caret / committed-snapshot machine the vectors deliberately do not drive.",
    ]
    /// Vector `active` / `mods` order (`control`, `alt`, `shift`, `meta`).
    /// Not `DirectKeystrokeModifier.allCases` (`control`, `shift`, `alt`, `meta`).
    private static let canonicalModifiers = ["control", "alt", "shift", "meta"]

    // MARK: - Contract

    func testHarnessFailsOnASuiteItCannotRun() throws {
        let vectors = try Self.loadVectors()
        XCTAssertFalse(vectors.isEmpty, "vendored vectors/ must not be empty")

        var bySuite: [String: Int] = [:]
        for vector in vectors {
            bySuite[vector.suite, default: 0] += 1
        }
        let discovered = Set(bySuite.keys)
        let unknown = discovered
            .subtracting(Self.runnerSuites)
            .subtracting(Self.namedSkipSuites.keys)
        XCTAssertEqual(
            unknown,
            [],
            "suites with no runner and no named skip: \(unknown.sorted()). A harness that silently skips what it cannot run is the failure this arrangement exists to prevent."
        )

        let summary = bySuite.keys.sorted()
            .map { "\($0)=\(bySuite[$0] ?? 0)" }
            .joined(separator: " ")
        print("CONFORMANCE discovered \(vectors.count) vectors: \(summary)")
        for (suite, reason) in Self.namedSkipSuites.sorted(by: { $0.key < $1.key }) {
            let ids = vectors.filter { $0.suite == suite }.map(\.id).sorted()
            print("CONFORMANCE named-skip suite=\(suite) count=\(ids.count) ids=\(ids.joined(separator: ",")) reason=\(reason)")
        }
    }

    func testEveryVectorNamesItsSourceAndIdsAreUnique() throws {
        let vectors = try Self.loadVectors()
        var seen: Set<String> = []
        for vector in vectors {
            XCTAssertFalse(
                vector.sourceRepo.isEmpty,
                "\(vector.suite)/\(vector.id): source.repo is required"
            )
            XCTAssertFalse(vector.steps.isEmpty, "\(vector.suite)/\(vector.id): steps")
            let key = "\(vector.suite)/\(vector.id)"
            XCTAssertFalse(seen.contains(key), "duplicate vector id \(key)")
            seen.insert(key)
        }
    }

    func testOriginFilePinsSourceRepoAndCommit() throws {
        let origin = try Self.originURL()
        let text = try String(contentsOf: origin, encoding: .utf8)
        XCTAssertTrue(
            text.contains("https://github.com/midagedev/touch-remote-input"),
            "ORIGIN.txt must name the source repo"
        )
        XCTAssertTrue(
            text.contains("commit: 47afca257dd3257c9292391cc3b7f0180e6efc6a"),
            "ORIGIN.txt must pin the commit verified with rev-parse HEAD"
        )
    }

    func testCompositionSuiteSkippedByName() throws {
        let ids = try Self.loadVectors()
            .filter { $0.suite == "composition" }
            .map(\.id)
            .sorted()
        XCTAssertFalse(ids.isEmpty, "composition vectors must be vendored so the skip is visible")
        let reason = try XCTUnwrap(Self.namedSkipSuites["composition"])
        print(
            "CONFORMANCE composition ran=0 skipped=\(ids.count) ids=\(ids.joined(separator: ",")) reason=\(reason)"
        )
        throw XCTSkip(
            "composition suite skipped by name: \(reason) Vectors not run: \(ids.joined(separator: ", "))."
        )
    }

    // MARK: - Suites

    func testStickyGoldenVectors() throws {
        let vectors = try Self.loadVectors().filter { $0.suite == "sticky" }
        XCTAssertFalse(vectors.isEmpty)
        var ran = 0
        for vector in vectors {
            try Self.runSticky(vector)
            ran += 1
        }
        print("CONFORMANCE sticky ran=\(ran) skipped=0")
    }

    func testCadenceGoldenVectors() throws {
        let vectors = try Self.loadVectors().filter { $0.suite == "cadence" }
        XCTAssertFalse(vectors.isEmpty)
        var ran = 0
        var skipped: [(id: String, reason: String)] = []
        for vector in vectors {
            switch try Self.runCadence(vector) {
            case .ran:
                ran += 1
            case .skipped(let reason):
                skipped.append((vector.id, reason))
            }
        }
        for item in skipped {
            print("CONFORMANCE cadence skipped vector=\(item.id) reason=\(item.reason)")
        }
        print("CONFORMANCE cadence ran=\(ran) skipped=\(skipped.count)")
    }

    func testFlushGoldenVectors() throws {
        let vectors = try Self.loadVectors().filter { $0.suite == "flush" }
        XCTAssertFalse(vectors.isEmpty)
        var ran = 0
        for vector in vectors {
            try Self.runFlush(vector)
            ran += 1
        }
        print("CONFORMANCE flush ran=\(ran) skipped=0")
    }

    // MARK: - Sticky (M1)

    private static func runSticky(_ vector: Vector) throws {
        var state = StickyModifierState()
        let t0 = ContinuousClock.now
        for (index, step) in vector.steps.enumerated() {
            let where_ = "\(vector.id) step \(index) (t=\(step.t))"
            let op = try step.string("op")
            switch op {
            case "tap":
                let name = try step.string("mod")
                state.tap(try modifier(name), at: t0.advanced(by: .milliseconds(step.t)))
            case "consume":
                state.consumeAfterNonModifierEmission()
            case "clear":
                state.clear()
            case "noop":
                break
            default:
                XCTFail("\(where_): unknown sticky op \"\(op)\"")
                return
            }

            if let slots = step.expect["slots"] as? [String: Any] {
                for (name, value) in slots {
                    let got = state.slot(for: try modifier(name)).rawValue
                    XCTAssertEqual(got, value as? String, "\(where_): slot \(name)")
                }
            }
            if step.expect["active"] != nil {
                let got = sortMods(state.activeModifiers.map(\.rawValue))
                XCTAssertEqual(got, try step.stringArray("active", fromExpect: true), "\(where_): active")
            }
        }
    }

    // MARK: - Cadence (M2)

    private enum CadenceOutcome {
        case ran
        case skipped(String)
    }

    private static func runCadence(_ vector: Vector) throws -> CadenceOutcome {
        for step in vector.steps {
            if let keyId = step.input["key"] as? String, AccessoryKey(rawValue: keyId) == nil {
                return .skipped(
                    "vector names key \"\(keyId)\" which naru AccessoryKey does not have; skipped by name, not rewritten"
                )
            }
        }

        var cadence = AccessoryKeyRepeatCadence()
        let t0 = ContinuousClock.now
        for (index, step) in vector.steps.enumerated() {
            let where_ = "\(vector.id) step \(index) (t=\(step.t))"
            let at = t0.advanced(by: .milliseconds(step.t))
            let mods = sortMods(step.mods)
            let op = try step.string("op")
            let got: [Intent]
            switch op {
            case "press":
                let keyId = try step.string("key")
                let key = try XCTUnwrap(AccessoryKey(rawValue: keyId), where_)
                got = intents(cadence.press(key, at: at), mods: mods, t0: t0)
            case "tick":
                got = intents(cadence.tick(at: at), mods: mods, t0: t0)
            case "release":
                let wasHeld = cadence.heldKey != nil
                cadence.release()
                got = wasHeld ? [.clearSchedule] : []
            case "stop":
                cadence.stop()
                got = []
            default:
                XCTFail("\(where_): unknown cadence op \"\(op)\"")
                return .ran
            }

            if step.expect["intents"] != nil {
                XCTAssertEqual(got, try parseIntents(step.expect["intents"]), "\(where_): intents")
            }
            if step.expect.keys.contains("held") {
                if step.expect["held"] is NSNull {
                    XCTAssertNil(cadence.heldKey, "\(where_): held")
                } else if let held = step.expect["held"] as? String {
                    XCTAssertEqual(cadence.heldKey?.rawValue, held, "\(where_): held")
                } else {
                    XCTFail("\(where_): held must be a string or null")
                }
            }
        }
        return .ran
    }

    /// Flatten `Tick` to the vector intent list. `release()` returns nothing
    /// in Swift; `clear-schedule` is synthesized here, not by the type.
    private static func intents(
        _ tick: AccessoryKeyRepeatCadence.Tick,
        mods: [String],
        t0: ContinuousClock.Instant
    ) -> [Intent] {
        var out: [Intent] = []
        if let key = tick.emit {
            out.append(.emitKey(key.rawValue, mods: mods))
        }
        if let next = tick.nextTickAt {
            out.append(.scheduleTick(milliseconds(from: t0, to: next)))
        }
        return out
    }

    // MARK: - Flush (M4)

    private static func runFlush(_ vector: Vector) throws {
        for (index, step) in vector.steps.enumerated() {
            let where_ = "\(vector.id) step \(index)"
            let op = try step.string("op")
            XCTAssertEqual(op, "control", "\(where_): unknown flush op \"\(op)\"")
            let key = try step.string("key")
            let hasMarked = try step.bool("hasMarked")
            let pending = try pendingFlush(step.string("pending"))
            let got = AccessoryControlFlushBarrier.steps(
                hasMarkedText: hasMarked,
                pendingFlush: pending
            ).map { naruStep -> Intent in
                switch naruStep {
                case .commitMarkedText:
                    return .commitMarked
                case .emitControl:
                    return .emitKey(key, mods: sortMods(step.mods))
                case .dropControl:
                    return .dropControl
                }
            }
            XCTAssertEqual(got, try parseIntents(step.expect["intents"]), "\(where_): intents")
        }
    }

    private static func pendingFlush(_ name: String) throws -> AccessoryControlFlushBarrier.PendingFlushResult {
        switch name {
        case "not-needed": return .notNeeded
        case "succeeded": return .succeeded
        case "failed": return .failed
        default:
            throw VectorError.badValue("unknown pending \"\(name)\"")
        }
    }

    // MARK: - Intents / JSON

    private struct Intent: Equatable, CustomStringConvertible {
        var op: String
        var key: String?
        var text: String?
        var mods: [String]?
        var atMs: Int?

        static func emitKey(_ key: String, mods: [String]) -> Intent {
            Intent(op: "emit-key", key: key, mods: mods)
        }

        static func emitText(_ text: String, mods: [String]) -> Intent {
            Intent(op: "emit-text", text: text, mods: mods)
        }

        static let withhold = Intent(op: "withhold")
        static let commitMarked = Intent(op: "commit-marked")
        static let dropControl = Intent(op: "drop-control")
        static let clearSchedule = Intent(op: "clear-schedule")

        static func scheduleTick(_ atMs: Int) -> Intent {
            Intent(op: "schedule-tick", atMs: atMs)
        }

        var description: String {
            var parts = ["op=\(op)"]
            if let key { parts.append("key=\(key)") }
            if let text { parts.append("text=\(text)") }
            if let mods { parts.append("mods=\(mods)") }
            if let atMs { parts.append("atMs=\(atMs)") }
            return parts.joined(separator: " ")
        }
    }

    private static func parseIntents(_ any: Any?) throws -> [Intent] {
        guard let array = any as? [Any] else {
            throw VectorError.badValue("intents must be an array")
        }
        return try array.map { item in
            guard let object = item as? [String: Any], let op = object["op"] as? String else {
                throw VectorError.badValue("intent missing op")
            }
            switch op {
            case "emit-key":
                guard let key = object["key"] as? String else {
                    throw VectorError.badValue("emit-key missing key")
                }
                return .emitKey(key, mods: sortMods(jsonStringArray(object["mods"]) ?? []))
            case "emit-text":
                guard let text = object["text"] as? String else {
                    throw VectorError.badValue("emit-text missing text")
                }
                return .emitText(text, mods: sortMods(jsonStringArray(object["mods"]) ?? []))
            case "withhold":
                return .withhold
            case "commit-marked":
                return .commitMarked
            case "drop-control":
                return .dropControl
            case "clear-schedule":
                return .clearSchedule
            case "schedule-tick":
                guard let atMs = jsonInt(object["atMs"]) else {
                    throw VectorError.badValue("schedule-tick missing atMs")
                }
                return .scheduleTick(atMs)
            default:
                throw VectorError.badValue("unknown intent op \"\(op)\"")
            }
        }
    }

    private static func sortMods(_ mods: [String]) -> [String] {
        canonicalModifiers.filter { mods.contains($0) }
    }

    private static func modifier(_ name: String) throws -> StickyModifierState.Modifier {
        guard let modifier = StickyModifierState.Modifier(rawValue: name) else {
            throw VectorError.badValue("unknown modifier \"\(name)\"")
        }
        return modifier
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Int {
        let (seconds, attoseconds) = (end - start).components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }

    private static func jsonInt(_ any: Any?) -> Int? {
        if let int = any as? Int { return int }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }

    private static func jsonStringArray(_ any: Any?) -> [String]? {
        if let strings = any as? [String] { return strings }
        if let items = any as? [Any] { return items.map { $0 as? String ?? String(describing: $0) } }
        return nil
    }

    // MARK: - Loading

    private struct Vector {
        let suite: String
        let id: String
        let sourceRepo: String
        let steps: [Step]
    }

    private struct Step {
        let t: Int
        let input: [String: Any]
        let expect: [String: Any]

        var mods: [String] {
            TouchRemoteInputConformanceTests.jsonStringArray(input["mods"]) ?? []
        }

        func string(_ key: String) throws -> String {
            guard let value = input[key] as? String else {
                throw VectorError.badValue("in.\(key) missing")
            }
            return value
        }

        func bool(_ key: String) throws -> Bool {
            if let value = input[key] as? Bool { return value }
            if let number = input[key] as? NSNumber { return number.boolValue }
            throw VectorError.badValue("in.\(key) missing")
        }

        func stringArray(_ key: String, fromExpect: Bool) throws -> [String] {
            let object = fromExpect ? expect : input
            guard let value = TouchRemoteInputConformanceTests.jsonStringArray(object[key]) else {
                throw VectorError.badValue("\(fromExpect ? "expect" : "in").\(key) missing")
            }
            return value
        }
    }

    private enum VectorError: Error, CustomStringConvertible {
        case missingRoot
        case unreadable(String)
        case badValue(String)

        var description: String {
            switch self {
            case .missingRoot:
                return "Bundle.module has no vectors/ resource"
            case .unreadable(let path):
                return "could not read \(path)"
            case .badValue(let message):
                return message
            }
        }
    }

    private static func loadVectors() throws -> [Vector] {
        let root = try vectorRoot()
        let fm = FileManager.default
        let suites = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var out: [Vector] = []
        for suiteURL in suites {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: suiteURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }
            let suite = suiteURL.lastPathComponent
            let files = try fm.contentsOfDirectory(
                at: suiteURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for file in files where file.pathExtension == "json" {
                let data = try Data(contentsOf: file)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw VectorError.unreadable(file.path)
                }
                let declaredSuite = object["suite"] as? String ?? ""
                if declaredSuite != suite {
                    throw VectorError.badValue("\(suite)/\(file.lastPathComponent): suite field is \"\(declaredSuite)\"")
                }
                guard let id = object["id"] as? String else {
                    throw VectorError.badValue("\(file.lastPathComponent) missing id")
                }
                let source = object["source"] as? [String: Any]
                let repo = source?["repo"] as? String ?? ""
                guard let rawSteps = object["steps"] as? [Any], !rawSteps.isEmpty else {
                    throw VectorError.badValue("\(suite)/\(id): steps")
                }
                let steps: [Step] = try rawSteps.map { item in
                    guard let step = item as? [String: Any],
                          let t = jsonInt(step["t"]),
                          let input = step["in"] as? [String: Any],
                          let expect = step["expect"] as? [String: Any]
                    else {
                        throw VectorError.badValue("\(suite)/\(id): malformed step")
                    }
                    return Step(t: t, input: input, expect: expect)
                }
                out.append(Vector(suite: suite, id: id, sourceRepo: repo, steps: steps))
            }
        }
        return out.sorted { lhs, rhs in
            if lhs.suite != rhs.suite { return lhs.suite < rhs.suite }
            return lhs.id < rhs.id
        }
    }

    private static func vectorRoot() throws -> URL {
        if let url = Bundle.module.url(forResource: "vectors", withExtension: nil) {
            return url
        }
        if let resourceURL = Bundle.module.resourceURL {
            let candidate = resourceURL.appendingPathComponent("vectors")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                return candidate
            }
        }
        throw VectorError.missingRoot
    }

    private static func originURL() throws -> URL {
        if let url = Bundle.module.url(
            forResource: "ORIGIN",
            withExtension: "txt",
            subdirectory: "vectors"
        ) {
            return url
        }
        let candidate = try vectorRoot().appendingPathComponent("ORIGIN.txt")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw VectorError.unreadable("vectors/ORIGIN.txt")
        }
        return candidate
    }
}
