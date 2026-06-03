import Foundation
import CryptoKit

public struct DiagnosticExport: Equatable, Sendable {
    public let runID: UUID
    public let profileFingerprint: String
    public let verdict: DiagnosticVerdict
    public let startedAt: Date
    public let finishedAt: Date?
    public let context: DiagnosticRunContext?
    public let streamPerformance: DiagnosticStreamPerformanceReport?
    /// Stage rows captured from the underlying
    /// `ConnectionDiagnosticRun`.  Stored as safe-catalog tuples
    /// (`stage.rawValue`, `status.rawValue`) so the formatter has no
    /// access to caller-supplied raw detail strings.  Constitution
    /// §IV: this struct is the only surface allowed to reach the
    /// share-text path.
    public let stageRows: [Row]
    public let summary: String

    public init(
        run: ConnectionDiagnosticRun,
        detailLevel: DiagnosticExportDetailLevel = .summaryOnly,
        streamPerformance: DiagnosticStreamPerformanceReport? = nil
    ) {
        self.runID = run.id
        self.profileFingerprint = Self.profileFingerprint(for: run.profileID)
        self.verdict = run.verdict
        self.startedAt = run.startedAt
        self.finishedAt = run.finishedAt
        self.context = run.context
        self.streamPerformance = streamPerformance

        let lines = run.stages.map { stage in
            var line = "\(stage.stage.rawValue)=\(stage.status.rawValue) \(stage.safeTitle)"
            if detailLevel == .stageSummary {
                line += ": \(DiagnosticExportSafeDetailCatalog.detail(for: stage))"
            }
            return line
        }

        self.summary = lines.joined(separator: "\n")
        self.stageRows = run.stages.map { stage in
            Row(
                stageID: stage.stage.rawValue,
                statusID: stage.status.rawValue,
                safeDetail: DiagnosticExportSafeDetailCatalog.detail(for: stage),
                recordedAt: Self.isoString(from: stage.timestamp),
                failureCode: DiagnosticFailureCodeCatalog.safeCode(stage.metadata?.failureCode)
            )
        }
    }

    /// Stage row used by the share-text formatter.  Carries only
    /// safe-catalog identifiers and the catalog detail string —
    /// never the caller-provided `safeTitle`/`safeDetail`/`nextAction`
    /// (constitution §IV).
    public struct Row: Codable, Equatable, Sendable {
        public let stageID: String
        public let statusID: String
        public let safeDetail: String
        public let recordedAt: String
        public let failureCode: String?

        public init(
            stageID: String,
            statusID: String,
            safeDetail: String,
            recordedAt: String,
            failureCode: String? = nil
        ) {
            self.stageID = stageID
            self.statusID = statusID
            self.safeDetail = safeDetail
            self.recordedAt = recordedAt
            self.failureCode = failureCode
        }
    }

    /// Plain-text rendering suitable for attaching to a support
    /// thread.  Header is `Naru Remote Diagnostic Summary — <ISO8601
    /// date> — Build <buildVersion ?? "n/a">`.  Body is one line per
    /// stage row using safe-catalog IDs only.  The `now` argument is
    /// injectable so tests can pin the timestamp.
    public func renderShareText(
        buildVersion: String?,
        now: Date = Date()
    ) -> String {
        let isoDate = Self.isoString(from: now)
        let buildToken = buildVersion ?? "n/a"
        let header = "Naru Remote Diagnostic Summary — \(isoDate) — Build \(buildToken)"

        if stageRows.isEmpty {
            return "\(header)\n(no diagnostic stages recorded)"
        }

        let body = stageRows.map { row in
            "[\(row.stageID)] \(row.statusID) — \(row.safeDetail)"
        }.joined(separator: "\n")

        return "\(header)\n\(body)"
    }

    public func makeCollectionReport(
        buildVersion: String?,
        now: Date = Date()
    ) -> DiagnosticCollectionReport {
        DiagnosticCollectionReport(
            generatedAt: Self.isoString(from: now),
            buildVersion: buildVersion ?? "n/a",
            runID: runID.uuidString.lowercased(),
            profileFingerprint: profileFingerprint,
            startedAt: Self.isoString(from: startedAt),
            finishedAt: finishedAt.map { Self.isoString(from: $0) },
            runDurationBucket: DiagnosticDurationBucket.bucket(
                startedAt: startedAt,
                finishedAt: finishedAt
            ).rawValue,
            targetFingerprint: context?.targetFingerprint,
            profileHostKind: context?.profileHostKind,
            configuredPort: context?.configuredPort,
            hasCredentialReference: context?.hasCredentialReference,
            diagnosticTrigger: context?.trigger?.rawValue,
            probeTimeoutSeconds: context?.probeTimeoutSeconds,
            verdict: verdict.rawValue,
            stageRows: stageRows,
            streamPerformance: streamPerformance
        )
    }

    public func renderCollectionJSON(
        buildVersion: String?,
        now: Date = Date()
    ) -> String {
        let report = makeCollectionReport(buildVersion: buildVersion, now: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Report fields are fixed String/Int/array values; encoding
        // failure would be a programmer error, and returning partial
        // JSON would break the collection contract.
        let data = try! encoder.encode(report)
        return String(decoding: data, as: UTF8.self)
    }

    public func renderSharePayload(
        buildVersion: String?,
        now: Date = Date()
    ) -> String {
        let text = renderShareText(buildVersion: buildVersion, now: now)
        let json = renderCollectionJSON(buildVersion: buildVersion, now: now)
        return "\(text)\n\n--- Naru Remote Diagnostic JSON v3 ---\n\(json)"
    }

    private static func isoString(from date: Date) -> String {
        // ISO8601 formatter is constructed per call rather than as a
        // `static let` because `ISO8601DateFormatter` is not
        // `Sendable` under Swift 6 strict concurrency, and the
        // share-text path is cold enough that the allocation cost is
        // not worth a global-actor wrapper.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func profileFingerprint(for profileID: UUID) -> String {
        DiagnosticFingerprint.sha256Token(profileID.uuidString.lowercased())
    }
}

public enum DiagnosticFingerprint {
    public static func sha256Token(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { byte in
            let value = String(byte, radix: 16)
            return value.count == 1 ? "0\(value)" : value
        }.joined()
        return "sha256:\(hex)"
    }
}

public enum DiagnosticExportDetailLevel: String, Codable, Equatable, Sendable {
    case summaryOnly
    case stageSummary
}

public enum DiagnosticFrameRateBucket: String, Codable, Equatable, Sendable {
    case notMeasured
    case underFive
    case fiveToFifteen
    case fifteenToTwentyFour
    case twentyFourToThirty
    case thirtyToSixty
    case sixtyOrMore

    public static func bucket(
        deliveredFrameCount: Int,
        observedDurationSeconds: TimeInterval?
    ) -> DiagnosticFrameRateBucket {
        guard deliveredFrameCount > 1,
              let observedDurationSeconds,
              observedDurationSeconds > 0
        else {
            return .notMeasured
        }

        let framesAfterFirst = max(deliveredFrameCount - 1, 0)
        let framesPerSecond = Double(framesAfterFirst) / observedDurationSeconds
        switch framesPerSecond {
        case ..<5:
            return .underFive
        case ..<15:
            return .fiveToFifteen
        case ..<24:
            return .fifteenToTwentyFour
        case ..<30:
            return .twentyFourToThirty
        case ..<60:
            return .thirtyToSixty
        default:
            return .sixtyOrMore
        }
    }
}

public struct DiagnosticStreamPerformanceReport: Codable, Equatable, Sendable {
    public let observedDurationBucket: String
    public let deliveredFramesPerSecondBucket: String
    public let deliveredFrameCount: Int
    public let contentFrameCount: Int
    public let emptyUpdateCount: Int
    public let transportIdleTimeoutCount: Int
    public let contentFramePermille: Int?
    public let emptyUpdatePermille: Int?
    public let transportIdleTimeoutPermille: Int?
    public let dirtyRectangleSampleCount: Int
    public let averageDirtyRectangleCount: Int?
    public let dirtyRectangleCountMax: Int
    public let averageDirtyAreaPermille: Int?
    public let dirtyAreaPermilleMax: Int
    public let averageChangedPixelsPermille: Int?
    public let changedPixelsPermilleMax: Int
    public let thermalState: String

    public init(
        observedDurationBucket: String,
        deliveredFramesPerSecondBucket: String,
        deliveredFrameCount: Int,
        contentFrameCount: Int,
        emptyUpdateCount: Int,
        transportIdleTimeoutCount: Int,
        contentFramePermille: Int? = nil,
        emptyUpdatePermille: Int? = nil,
        transportIdleTimeoutPermille: Int? = nil,
        dirtyRectangleSampleCount: Int,
        averageDirtyRectangleCount: Int? = nil,
        dirtyRectangleCountMax: Int,
        averageDirtyAreaPermille: Int? = nil,
        dirtyAreaPermilleMax: Int,
        averageChangedPixelsPermille: Int? = nil,
        changedPixelsPermilleMax: Int,
        thermalState: String
    ) {
        self.observedDurationBucket = Self.safeDurationBucket(observedDurationBucket)
        self.deliveredFramesPerSecondBucket = Self.safeFrameRateBucket(deliveredFramesPerSecondBucket)
        self.deliveredFrameCount = max(deliveredFrameCount, 0)
        self.contentFrameCount = max(contentFrameCount, 0)
        self.emptyUpdateCount = max(emptyUpdateCount, 0)
        self.transportIdleTimeoutCount = max(transportIdleTimeoutCount, 0)
        self.contentFramePermille = Self.clampPermille(contentFramePermille)
        self.emptyUpdatePermille = Self.clampPermille(emptyUpdatePermille)
        self.transportIdleTimeoutPermille = Self.clampPermille(transportIdleTimeoutPermille)
        self.dirtyRectangleSampleCount = max(dirtyRectangleSampleCount, 0)
        self.averageDirtyRectangleCount = averageDirtyRectangleCount.map { max($0, 0) }
        self.dirtyRectangleCountMax = max(dirtyRectangleCountMax, 0)
        self.averageDirtyAreaPermille = Self.clampPermille(averageDirtyAreaPermille)
        self.dirtyAreaPermilleMax = Self.clampPermille(dirtyAreaPermilleMax) ?? 0
        self.averageChangedPixelsPermille = Self.clampPermille(averageChangedPixelsPermille)
        self.changedPixelsPermilleMax = Self.clampPermille(changedPixelsPermilleMax) ?? 0
        self.thermalState = Self.safeThermalState(thermalState)
    }

    private static func clampPermille(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 1_000) }
    }

    private static func safeDurationBucket(_ value: String) -> String {
        DiagnosticDurationBucket(rawValue: value)?.rawValue ?? DiagnosticDurationBucket.notMeasured.rawValue
    }

    private static func safeFrameRateBucket(_ value: String) -> String {
        DiagnosticFrameRateBucket(rawValue: value)?.rawValue ?? DiagnosticFrameRateBucket.notMeasured.rawValue
    }

    private static func safeThermalState(_ value: String) -> String {
        let allowedValues = Set(["unknown", "nominal", "fair", "serious", "critical"])
        return allowedValues.contains(value) ? value : "unknown"
    }
}

public enum DiagnosticFailureCodeCatalog {
    private static let allowedCodes: Set<String> = [
        "credential.passwordMissing",
        "error.unknown",
        "network.connectTimedOut",
        "network.connectionFailed",
        "network.invalidPort",
        "network.notConnected",
        "network.readTimedOut",
        "network.timedOut",
        "network.writeTimedOut",
        "network.writeFailed",
        "rfb.authenticationRequired",
        "rfb.incompleteTranscript",
        "rfb.insufficientData",
        "rfb.invalidProtocolVersion",
        "rfb.invalidServerCutTextEncoding",
        "rfb.securityFailed",
        "rfb.truncatedServerCutText",
        "rfb.unexpectedMessageType",
        "rfb.unsupportedFramebufferEncoding",
        "rfb.unsupportedSecurityTypes"
    ]

    public static func safeCode(_ code: String?) -> String? {
        guard let code else {
            return nil
        }
        guard allowedCodes.contains(code) else {
            return "error.unknown"
        }
        return code
    }
}

public struct DiagnosticCollectionReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let generatedAt: String
    public let buildVersion: String
    public let runID: String
    public let profileFingerprint: String
    public let startedAt: String
    public let finishedAt: String?
    public let runDurationBucket: String
    public let targetFingerprint: String?
    public let profileHostKind: String?
    public let configuredPort: Int?
    public let hasCredentialReference: Bool?
    public let diagnosticTrigger: String?
    public let probeTimeoutSeconds: Double?
    public let verdict: String
    public let stageRows: [DiagnosticExport.Row]
    public let streamPerformance: DiagnosticStreamPerformanceReport?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        generatedAt: String,
        buildVersion: String,
        runID: String,
        profileFingerprint: String,
        startedAt: String,
        finishedAt: String?,
        runDurationBucket: String,
        targetFingerprint: String? = nil,
        profileHostKind: String? = nil,
        configuredPort: Int? = nil,
        hasCredentialReference: Bool? = nil,
        diagnosticTrigger: String? = nil,
        probeTimeoutSeconds: Double? = nil,
        verdict: String,
        stageRows: [DiagnosticExport.Row],
        streamPerformance: DiagnosticStreamPerformanceReport? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.buildVersion = buildVersion
        self.runID = runID
        self.profileFingerprint = profileFingerprint
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.runDurationBucket = runDurationBucket
        self.targetFingerprint = targetFingerprint
        self.profileHostKind = profileHostKind
        self.configuredPort = configuredPort
        self.hasCredentialReference = hasCredentialReference
        self.diagnosticTrigger = diagnosticTrigger
        self.probeTimeoutSeconds = probeTimeoutSeconds
        self.verdict = verdict
        self.stageRows = stageRows
        self.streamPerformance = streamPerformance
    }
}

public enum DiagnosticExportSafeDetailCatalog {
    public static func detail(for stage: DiagnosticStageResult) -> String {
        switch stage.stage {
        case .dns:
            return "Name resolution stage."
        case .tcp:
            return "TCP reachability stage."
        case .rfbHandshake:
            return "VNC handshake stage."
        case .authentication:
            return "Authentication stage."
        case .firstFrame:
            return "Remote frame receive stage."
        case .clipboardText:
            return "Remote text clipboard stage."
        }
    }
}
