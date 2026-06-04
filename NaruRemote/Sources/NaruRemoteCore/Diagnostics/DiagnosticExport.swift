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
    public let viewerStreamPowerMode: StreamPowerMode?
    public let input: DiagnosticInputReport?
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
        streamPerformance: DiagnosticStreamPerformanceReport? = nil,
        viewerStreamPowerMode: StreamPowerMode? = nil,
        input: DiagnosticInputReport? = nil
    ) {
        self.runID = run.id
        self.profileFingerprint = Self.profileFingerprint(for: run.profileID)
        self.verdict = run.verdict
        self.startedAt = run.startedAt
        self.finishedAt = run.finishedAt
        self.context = run.context
        self.streamPerformance = streamPerformance
        self.viewerStreamPowerMode = viewerStreamPowerMode
        self.input = input

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
            streamPerformance: streamPerformance,
            viewerStreamPowerMode: viewerStreamPowerMode?.rawValue,
            input: input
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
        return "\(text)\n\n--- Naru Remote Diagnostic JSON v\(DiagnosticCollectionReport.currentSchemaVersion) ---\n\(json)"
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

public enum DiagnosticTimingBucket: String, Codable, Equatable, Sendable {
    case notMeasured
    case subFrame
    case interactive
    case lagging
    case stalled

    public static func bucket(milliseconds: Int?) -> DiagnosticTimingBucket {
        guard let milliseconds, milliseconds >= 0 else {
            return .notMeasured
        }

        switch milliseconds {
        case ..<16:
            return .subFrame
        case ..<80:
            return .interactive
        case ..<250:
            return .lagging
        default:
            return .stalled
        }
    }
}

public struct DiagnosticStreamPerformanceReport: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case observedDurationBucket
        case deliveredFramesPerSecondBucket
        case deliveredFrameCount
        case contentFrameCount
        case emptyUpdateCount
        case transportIdleTimeoutCount
        case contentFramePermille
        case emptyUpdatePermille
        case transportIdleTimeoutPermille
        case adaptiveClientPressurePacingSampleCount
        case adaptiveClientPressurePacingPermille
        case dirtyRectangleSampleCount
        case averageDirtyRectangleCount
        case dirtyRectangleCountMax
        case averageDirtyAreaPermille
        case dirtyAreaPermilleMax
        case averageChangedPixelsPermille
        case changedPixelsPermilleMax
        case rendererUploadSampleCount
        case rendererPartialUploadCount
        case rendererFullUploadCount
        case rendererPartialUploadPermille
        case rendererFullUploadPermille
        case rendererUploadRegionCountMax
        case receiveTimingSampleCount
        case averageReceiveTotalTimingBucket
        case maxReceiveTotalTimingBucket
        case averageNetworkReadTimingBucket
        case maxNetworkReadTimingBucket
        case averageClientProcessingTimingBucket
        case maxClientProcessingTimingBucket
        case actualEncodingMix
        case thermalState
    }

    public let observedDurationBucket: String
    public let deliveredFramesPerSecondBucket: String
    public let deliveredFrameCount: Int
    public let contentFrameCount: Int
    public let emptyUpdateCount: Int
    public let transportIdleTimeoutCount: Int
    public let contentFramePermille: Int?
    public let emptyUpdatePermille: Int?
    public let transportIdleTimeoutPermille: Int?
    public let adaptiveClientPressurePacingSampleCount: Int
    public let adaptiveClientPressurePacingPermille: Int
    public let dirtyRectangleSampleCount: Int
    public let averageDirtyRectangleCount: Int?
    public let dirtyRectangleCountMax: Int
    public let averageDirtyAreaPermille: Int?
    public let dirtyAreaPermilleMax: Int
    public let averageChangedPixelsPermille: Int?
    public let changedPixelsPermilleMax: Int
    public let rendererUploadSampleCount: Int
    public let rendererPartialUploadCount: Int
    public let rendererFullUploadCount: Int
    public let rendererPartialUploadPermille: Int?
    public let rendererFullUploadPermille: Int?
    public let rendererUploadRegionCountMax: Int
    public let receiveTimingSampleCount: Int
    public let averageReceiveTotalTimingBucket: String
    public let maxReceiveTotalTimingBucket: String
    public let averageNetworkReadTimingBucket: String
    public let maxNetworkReadTimingBucket: String
    public let averageClientProcessingTimingBucket: String
    public let maxClientProcessingTimingBucket: String
    public let actualEncodingMix: RFBFramebufferEncodingMix
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
        adaptiveClientPressurePacingSampleCount: Int = 0,
        adaptiveClientPressurePacingPermille: Int? = nil,
        dirtyRectangleSampleCount: Int,
        averageDirtyRectangleCount: Int? = nil,
        dirtyRectangleCountMax: Int,
        averageDirtyAreaPermille: Int? = nil,
        dirtyAreaPermilleMax: Int,
        averageChangedPixelsPermille: Int? = nil,
        changedPixelsPermilleMax: Int,
        rendererUploadSampleCount: Int = 0,
        rendererPartialUploadCount: Int = 0,
        rendererFullUploadCount: Int = 0,
        rendererPartialUploadPermille: Int? = nil,
        rendererFullUploadPermille: Int? = nil,
        rendererUploadRegionCountMax: Int = 0,
        receiveTimingSampleCount: Int = 0,
        averageReceiveTotalTimingBucket: String = DiagnosticTimingBucket.notMeasured.rawValue,
        maxReceiveTotalTimingBucket: String = DiagnosticTimingBucket.notMeasured.rawValue,
        averageNetworkReadTimingBucket: String = DiagnosticTimingBucket.notMeasured.rawValue,
        maxNetworkReadTimingBucket: String = DiagnosticTimingBucket.notMeasured.rawValue,
        averageClientProcessingTimingBucket: String = DiagnosticTimingBucket.notMeasured.rawValue,
        maxClientProcessingTimingBucket: String = DiagnosticTimingBucket.notMeasured.rawValue,
        actualEncodingMix: RFBFramebufferEncodingMix = RFBFramebufferEncodingMix(),
        thermalState: String
    ) {
        self.observedDurationBucket = Self.safeDurationBucket(observedDurationBucket)
        self.deliveredFramesPerSecondBucket = Self.safeFrameRateBucket(deliveredFramesPerSecondBucket)
        let deliveredFrameCount = max(deliveredFrameCount, 0)
        self.deliveredFrameCount = deliveredFrameCount
        self.contentFrameCount = max(contentFrameCount, 0)
        self.emptyUpdateCount = max(emptyUpdateCount, 0)
        self.transportIdleTimeoutCount = max(transportIdleTimeoutCount, 0)
        self.contentFramePermille = Self.clampPermille(contentFramePermille)
        self.emptyUpdatePermille = Self.clampPermille(emptyUpdatePermille)
        self.transportIdleTimeoutPermille = Self.clampPermille(transportIdleTimeoutPermille)
        let adaptiveClientPressurePacingSampleCount = min(
            max(adaptiveClientPressurePacingSampleCount, 0),
            deliveredFrameCount
        )
        self.adaptiveClientPressurePacingSampleCount = adaptiveClientPressurePacingSampleCount
        if deliveredFrameCount == 0 {
            self.adaptiveClientPressurePacingPermille = 0
        } else {
            self.adaptiveClientPressurePacingPermille = Self.clampPermille(
                adaptiveClientPressurePacingPermille
                    ?? Self.permille(adaptiveClientPressurePacingSampleCount, of: deliveredFrameCount)
            ) ?? 0
        }
        self.dirtyRectangleSampleCount = max(dirtyRectangleSampleCount, 0)
        self.averageDirtyRectangleCount = averageDirtyRectangleCount.map { max($0, 0) }
        self.dirtyRectangleCountMax = max(dirtyRectangleCountMax, 0)
        self.averageDirtyAreaPermille = Self.clampPermille(averageDirtyAreaPermille)
        self.dirtyAreaPermilleMax = Self.clampPermille(dirtyAreaPermilleMax) ?? 0
        self.averageChangedPixelsPermille = Self.clampPermille(averageChangedPixelsPermille)
        self.changedPixelsPermilleMax = Self.clampPermille(changedPixelsPermilleMax) ?? 0
        self.rendererUploadSampleCount = max(rendererUploadSampleCount, 0)
        self.rendererPartialUploadCount = max(rendererPartialUploadCount, 0)
        self.rendererFullUploadCount = max(rendererFullUploadCount, 0)
        self.rendererPartialUploadPermille = Self.clampPermille(rendererPartialUploadPermille)
        self.rendererFullUploadPermille = Self.clampPermille(rendererFullUploadPermille)
        self.rendererUploadRegionCountMax = max(rendererUploadRegionCountMax, 0)
        let receiveTimingSampleCount = max(receiveTimingSampleCount, 0)
        self.receiveTimingSampleCount = receiveTimingSampleCount
        if receiveTimingSampleCount == 0 {
            self.averageReceiveTotalTimingBucket = DiagnosticTimingBucket.notMeasured.rawValue
            self.maxReceiveTotalTimingBucket = DiagnosticTimingBucket.notMeasured.rawValue
            self.averageNetworkReadTimingBucket = DiagnosticTimingBucket.notMeasured.rawValue
            self.maxNetworkReadTimingBucket = DiagnosticTimingBucket.notMeasured.rawValue
            self.averageClientProcessingTimingBucket = DiagnosticTimingBucket.notMeasured.rawValue
            self.maxClientProcessingTimingBucket = DiagnosticTimingBucket.notMeasured.rawValue
        } else {
            self.averageReceiveTotalTimingBucket = Self.safeTimingBucket(averageReceiveTotalTimingBucket)
            self.maxReceiveTotalTimingBucket = Self.safeTimingBucket(maxReceiveTotalTimingBucket)
            self.averageNetworkReadTimingBucket = Self.safeTimingBucket(averageNetworkReadTimingBucket)
            self.maxNetworkReadTimingBucket = Self.safeTimingBucket(maxNetworkReadTimingBucket)
            self.averageClientProcessingTimingBucket = Self.safeTimingBucket(averageClientProcessingTimingBucket)
            self.maxClientProcessingTimingBucket = Self.safeTimingBucket(maxClientProcessingTimingBucket)
        }
        self.actualEncodingMix = Self.safeEncodingMix(actualEncodingMix)
        self.thermalState = Self.safeThermalState(thermalState)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            observedDurationBucket: try container.decode(String.self, forKey: .observedDurationBucket),
            deliveredFramesPerSecondBucket: try container.decode(
                String.self,
                forKey: .deliveredFramesPerSecondBucket
            ),
            deliveredFrameCount: try container.decode(Int.self, forKey: .deliveredFrameCount),
            contentFrameCount: try container.decode(Int.self, forKey: .contentFrameCount),
            emptyUpdateCount: try container.decode(Int.self, forKey: .emptyUpdateCount),
            transportIdleTimeoutCount: try container.decode(Int.self, forKey: .transportIdleTimeoutCount),
            contentFramePermille: try container.decodeIfPresent(Int.self, forKey: .contentFramePermille),
            emptyUpdatePermille: try container.decodeIfPresent(Int.self, forKey: .emptyUpdatePermille),
            transportIdleTimeoutPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .transportIdleTimeoutPermille
            ),
            adaptiveClientPressurePacingSampleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .adaptiveClientPressurePacingSampleCount
            ) ?? 0,
            adaptiveClientPressurePacingPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .adaptiveClientPressurePacingPermille
            ),
            dirtyRectangleSampleCount: try container.decode(Int.self, forKey: .dirtyRectangleSampleCount),
            averageDirtyRectangleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .averageDirtyRectangleCount
            ),
            dirtyRectangleCountMax: try container.decode(Int.self, forKey: .dirtyRectangleCountMax),
            averageDirtyAreaPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageDirtyAreaPermille
            ),
            dirtyAreaPermilleMax: try container.decode(Int.self, forKey: .dirtyAreaPermilleMax),
            averageChangedPixelsPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageChangedPixelsPermille
            ),
            changedPixelsPermilleMax: try container.decode(Int.self, forKey: .changedPixelsPermilleMax),
            rendererUploadSampleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .rendererUploadSampleCount
            ) ?? 0,
            rendererPartialUploadCount: try container.decodeIfPresent(
                Int.self,
                forKey: .rendererPartialUploadCount
            ) ?? 0,
            rendererFullUploadCount: try container.decodeIfPresent(
                Int.self,
                forKey: .rendererFullUploadCount
            ) ?? 0,
            rendererPartialUploadPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .rendererPartialUploadPermille
            ),
            rendererFullUploadPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .rendererFullUploadPermille
            ),
            rendererUploadRegionCountMax: try container.decodeIfPresent(
                Int.self,
                forKey: .rendererUploadRegionCountMax
            ) ?? 0,
            receiveTimingSampleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .receiveTimingSampleCount
            ) ?? 0,
            averageReceiveTotalTimingBucket: try container.decodeIfPresent(
                String.self,
                forKey: .averageReceiveTotalTimingBucket
            ) ?? DiagnosticTimingBucket.notMeasured.rawValue,
            maxReceiveTotalTimingBucket: try container.decodeIfPresent(
                String.self,
                forKey: .maxReceiveTotalTimingBucket
            ) ?? DiagnosticTimingBucket.notMeasured.rawValue,
            averageNetworkReadTimingBucket: try container.decodeIfPresent(
                String.self,
                forKey: .averageNetworkReadTimingBucket
            ) ?? DiagnosticTimingBucket.notMeasured.rawValue,
            maxNetworkReadTimingBucket: try container.decodeIfPresent(
                String.self,
                forKey: .maxNetworkReadTimingBucket
            ) ?? DiagnosticTimingBucket.notMeasured.rawValue,
            averageClientProcessingTimingBucket: try container.decodeIfPresent(
                String.self,
                forKey: .averageClientProcessingTimingBucket
            ) ?? DiagnosticTimingBucket.notMeasured.rawValue,
            maxClientProcessingTimingBucket: try container.decodeIfPresent(
                String.self,
                forKey: .maxClientProcessingTimingBucket
            ) ?? DiagnosticTimingBucket.notMeasured.rawValue,
            actualEncodingMix: try container.decodeIfPresent(
                RFBFramebufferEncodingMix.self,
                forKey: .actualEncodingMix
            ) ?? RFBFramebufferEncodingMix(),
            thermalState: try container.decode(String.self, forKey: .thermalState)
        )
    }

    private static func clampPermille(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 1_000) }
    }

    private static func permille(_ value: Int, of total: Int) -> Int {
        guard total > 0 else {
            return 0
        }
        let rounded = Int((Double(max(value, 0)) / Double(total) * 1_000).rounded())
        return value > 0 ? max(rounded, 1) : 0
    }

    private static func safeDurationBucket(_ value: String) -> String {
        DiagnosticDurationBucket(rawValue: value)?.rawValue ?? DiagnosticDurationBucket.notMeasured.rawValue
    }

    private static func safeFrameRateBucket(_ value: String) -> String {
        DiagnosticFrameRateBucket(rawValue: value)?.rawValue ?? DiagnosticFrameRateBucket.notMeasured.rawValue
    }

    private static func safeTimingBucket(_ value: String) -> String {
        DiagnosticTimingBucket(rawValue: value)?.rawValue ?? DiagnosticTimingBucket.notMeasured.rawValue
    }

    private static func safeEncodingMix(_ value: RFBFramebufferEncodingMix) -> RFBFramebufferEncodingMix {
        RFBFramebufferEncodingMix(
            rawRectangles: value.rawRectangles,
            copyRectRectangles: value.copyRectRectangles,
            hextileRectangles: value.hextileRectangles,
            zrleRectangles: value.zrleRectangles,
            tightRectangles: value.tightRectangles,
            cursorRectangles: value.cursorRectangles,
            xCursorRectangles: value.xCursorRectangles,
            desktopSizeRectangles: value.desktopSizeRectangles,
            extendedDesktopSizeRectangles: value.extendedDesktopSizeRectangles,
            lastRectRectangles: value.lastRectRectangles,
            endOfContinuousUpdatesEvents: value.endOfContinuousUpdatesEvents
        )
    }

    private static func safeThermalState(_ value: String) -> String {
        let allowedValues = Set(["unknown", "nominal", "fair", "serious", "critical"])
        return allowedValues.contains(value) ? value : "unknown"
    }
}

public struct DiagnosticInputReport: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case directKeystrokeModeActive
        case hasComposeDraftText
        case composeSendState
        case latestInjectionPath
        case latestInjectionStatus
        case latestInjectionPasteCommand
        case latestInjectionPayloadEncoding
        case latestInjectionClipboardSetStatus
        case latestInjectionPasteCommandStatus
        case latestInjectionRemoteClipboardRestore
        case latestInjectionDurationBucket
    }

    public let directKeystrokeModeActive: Bool?
    public let hasComposeDraftText: Bool?
    public let composeSendState: String?
    public let latestInjectionPath: String?
    public let latestInjectionStatus: String?
    public let latestInjectionPasteCommand: String?
    public let latestInjectionPayloadEncoding: String?
    public let latestInjectionClipboardSetStatus: String?
    public let latestInjectionPasteCommandStatus: String?
    public let latestInjectionRemoteClipboardRestore: String?
    public let latestInjectionDurationBucket: String?

    public init(
        directKeystrokeModeActive: Bool? = nil,
        hasComposeDraftText: Bool? = nil,
        composeSendState: String? = nil,
        latestInjectionPath: String? = nil,
        latestInjectionStatus: String? = nil,
        latestInjectionPasteCommand: String? = nil,
        latestInjectionPayloadEncoding: String? = nil,
        latestInjectionClipboardSetStatus: String? = nil,
        latestInjectionPasteCommandStatus: String? = nil,
        latestInjectionRemoteClipboardRestore: String? = nil,
        latestInjectionDurationBucket: String? = nil
    ) {
        self.directKeystrokeModeActive = directKeystrokeModeActive
        self.hasComposeDraftText = hasComposeDraftText
        self.composeSendState = Self.safeComposeSendState(composeSendState)
        self.latestInjectionPath = Self.safeInjectionPath(latestInjectionPath)
        self.latestInjectionStatus = Self.safeInjectionStatus(latestInjectionStatus)
        self.latestInjectionPasteCommand = Self.safePasteCommand(latestInjectionPasteCommand)
        self.latestInjectionPayloadEncoding = Self.safePayloadEncoding(latestInjectionPayloadEncoding)
        self.latestInjectionClipboardSetStatus = Self.safeInjectionStepStatus(latestInjectionClipboardSetStatus)
        self.latestInjectionPasteCommandStatus = Self.safeInjectionStepStatus(latestInjectionPasteCommandStatus)
        self.latestInjectionRemoteClipboardRestore = Self.safeRemoteClipboardRestore(
            latestInjectionRemoteClipboardRestore
        )
        self.latestInjectionDurationBucket = Self.safeDurationBucket(latestInjectionDurationBucket)
    }

    public init(
        composeDraft: ComposeDraft?,
        latestInjectionAttempt: TextInjectionAttempt?,
        directKeystrokeModeActive: Bool
    ) {
        self.init(
            directKeystrokeModeActive: directKeystrokeModeActive,
            hasComposeDraftText: composeDraft.map { !$0.text.isEmpty },
            composeSendState: composeDraft?.sendState.rawValue,
            latestInjectionPath: latestInjectionAttempt?.path.rawValue,
            latestInjectionStatus: latestInjectionAttempt?.status.rawValue,
            latestInjectionPasteCommand: latestInjectionAttempt?.pasteCommand?.rawValue,
            latestInjectionPayloadEncoding: latestInjectionAttempt?.payloadEncoding?.rawValue,
            latestInjectionClipboardSetStatus: latestInjectionAttempt?.clipboardSetStatus.rawValue,
            latestInjectionPasteCommandStatus: latestInjectionAttempt?.pasteCommandStatus.rawValue,
            latestInjectionRemoteClipboardRestore: latestInjectionAttempt?.remoteClipboardRestore.rawValue,
            latestInjectionDurationBucket: latestInjectionAttempt.map {
                DiagnosticDurationBucket.bucket(
                    startedAt: $0.startedAt,
                    finishedAt: $0.finishedAt
                ).rawValue
            }
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            directKeystrokeModeActive: try container.decodeIfPresent(
                Bool.self,
                forKey: .directKeystrokeModeActive
            ),
            hasComposeDraftText: try container.decodeIfPresent(Bool.self, forKey: .hasComposeDraftText),
            composeSendState: try container.decodeIfPresent(String.self, forKey: .composeSendState),
            latestInjectionPath: try container.decodeIfPresent(String.self, forKey: .latestInjectionPath),
            latestInjectionStatus: try container.decodeIfPresent(String.self, forKey: .latestInjectionStatus),
            latestInjectionPasteCommand: try container.decodeIfPresent(
                String.self,
                forKey: .latestInjectionPasteCommand
            ),
            latestInjectionPayloadEncoding: try container.decodeIfPresent(
                String.self,
                forKey: .latestInjectionPayloadEncoding
            ),
            latestInjectionClipboardSetStatus: try container.decodeIfPresent(
                String.self,
                forKey: .latestInjectionClipboardSetStatus
            ),
            latestInjectionPasteCommandStatus: try container.decodeIfPresent(
                String.self,
                forKey: .latestInjectionPasteCommandStatus
            ),
            latestInjectionRemoteClipboardRestore: try container.decodeIfPresent(
                String.self,
                forKey: .latestInjectionRemoteClipboardRestore
            ),
            latestInjectionDurationBucket: try container.decodeIfPresent(
                String.self,
                forKey: .latestInjectionDurationBucket
            )
        )
    }

    private static func safeComposeSendState(_ value: String?) -> String? {
        safe(value, allowed: Set(ComposeSendState.allCases.map(\.rawValue)))
    }

    private static func safeInjectionPath(_ value: String?) -> String? {
        safe(value, allowed: Set(TextInjectionPath.allCases.map(\.rawValue)))
    }

    private static func safeInjectionStatus(_ value: String?) -> String? {
        safe(value, allowed: Set(TextInjectionStatus.allCases.map(\.rawValue)))
    }

    private static func safePasteCommand(_ value: String?) -> String? {
        safe(value, allowed: Set(PasteCommand.allCases.map(\.rawValue)))
    }

    private static func safePayloadEncoding(_ value: String?) -> String? {
        safe(value, allowed: Set(TextInjectionPayloadEncoding.allCases.map(\.rawValue)))
    }

    private static func safeInjectionStepStatus(_ value: String?) -> String? {
        safe(value, allowed: Set(TextInjectionStepStatus.allCases.map(\.rawValue)))
    }

    private static func safeRemoteClipboardRestore(_ value: String?) -> String? {
        safe(value, allowed: Set(RemoteClipboardRestoreStatus.allCases.map(\.rawValue)))
    }

    private static func safeDurationBucket(_ value: String?) -> String? {
        safe(value, allowed: Set(DiagnosticDurationBucket.allCases.map(\.rawValue)))
    }

    private static func safe(_ value: String?, allowed: Set<String>) -> String? {
        guard let value else {
            return nil
        }
        return allowed.contains(value) ? value : nil
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
    public static let currentSchemaVersion = 10

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case buildVersion
        case runID
        case profileFingerprint
        case startedAt
        case finishedAt
        case runDurationBucket
        case targetFingerprint
        case profileHostKind
        case configuredPort
        case hasCredentialReference
        case diagnosticTrigger
        case probeTimeoutSeconds
        case verdict
        case stageRows
        case streamPerformance
        case viewerStreamPowerMode
        case input
    }

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
    public let viewerStreamPowerMode: String?
    public let input: DiagnosticInputReport?

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
        streamPerformance: DiagnosticStreamPerformanceReport? = nil,
        viewerStreamPowerMode: String? = nil,
        input: DiagnosticInputReport? = nil
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
        self.viewerStreamPowerMode = Self.safeViewerStreamPowerMode(viewerStreamPowerMode)
        self.input = input
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            generatedAt: try container.decode(String.self, forKey: .generatedAt),
            buildVersion: try container.decode(String.self, forKey: .buildVersion),
            runID: try container.decode(String.self, forKey: .runID),
            profileFingerprint: try container.decode(String.self, forKey: .profileFingerprint),
            startedAt: try container.decode(String.self, forKey: .startedAt),
            finishedAt: try container.decodeIfPresent(String.self, forKey: .finishedAt),
            runDurationBucket: try container.decode(String.self, forKey: .runDurationBucket),
            targetFingerprint: try container.decodeIfPresent(String.self, forKey: .targetFingerprint),
            profileHostKind: try container.decodeIfPresent(String.self, forKey: .profileHostKind),
            configuredPort: try container.decodeIfPresent(Int.self, forKey: .configuredPort),
            hasCredentialReference: try container.decodeIfPresent(Bool.self, forKey: .hasCredentialReference),
            diagnosticTrigger: try container.decodeIfPresent(String.self, forKey: .diagnosticTrigger),
            probeTimeoutSeconds: try container.decodeIfPresent(Double.self, forKey: .probeTimeoutSeconds),
            verdict: try container.decode(String.self, forKey: .verdict),
            stageRows: try container.decode([DiagnosticExport.Row].self, forKey: .stageRows),
            streamPerformance: try container.decodeIfPresent(
                DiagnosticStreamPerformanceReport.self,
                forKey: .streamPerformance
            ),
            viewerStreamPowerMode: try container.decodeIfPresent(String.self, forKey: .viewerStreamPowerMode),
            input: try container.decodeIfPresent(DiagnosticInputReport.self, forKey: .input)
        )
    }

    private static func safeViewerStreamPowerMode(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let allowedValues = Set(StreamPowerMode.allCases.map(\.rawValue))
        return allowedValues.contains(value) ? value : nil
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
