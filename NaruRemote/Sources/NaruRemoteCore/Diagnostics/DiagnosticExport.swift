import Foundation

public struct DiagnosticExport: Equatable, Sendable {
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
