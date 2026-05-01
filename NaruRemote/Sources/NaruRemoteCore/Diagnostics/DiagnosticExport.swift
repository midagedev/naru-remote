import Foundation

public struct DiagnosticExport: Equatable, Sendable {
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
        detailLevel: DiagnosticExportDetailLevel = .summaryOnly
    ) {
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
                safeDetail: DiagnosticExportSafeDetailCatalog.detail(for: stage)
            )
        }
    }

    /// Stage row used by the share-text formatter.  Carries only
    /// safe-catalog identifiers and the catalog detail string —
    /// never the caller-provided `safeTitle`/`safeDetail`/`nextAction`
    /// (constitution §IV).
    public struct Row: Equatable, Sendable {
        public let stageID: String
        public let statusID: String
        public let safeDetail: String

        public init(stageID: String, statusID: String, safeDetail: String) {
            self.stageID = stageID
            self.statusID = statusID
            self.safeDetail = safeDetail
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
        // ISO8601 formatter is constructed per call rather than as a
        // `static let` because `ISO8601DateFormatter` is not
        // `Sendable` under Swift 6 strict concurrency, and the
        // share-text path is cold enough that the allocation cost is
        // not worth a global-actor wrapper.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let isoDate = formatter.string(from: now)
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
}

public enum DiagnosticExportDetailLevel: String, Codable, Equatable, Sendable {
    case summaryOnly
    case stageSummary
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
