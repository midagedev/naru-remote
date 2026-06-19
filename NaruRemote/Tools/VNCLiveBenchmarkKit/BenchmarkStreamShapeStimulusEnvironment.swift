public enum BenchmarkStreamShapeStimulusEnvironment {
    public static let commandKey = "NARU_LIVE_STIMULUS_COMMAND"
    public static let durationKey = "NARU_LIVE_STIMULUS_DURATION_SECONDS"
    public static let frameIntervalKey = "NARU_LIVE_STIMULUS_FRAME_INTERVAL_SECONDS"
    public static let profileLabelKey = "NARU_LIVE_STIMULUS_PROFILE_LABEL"
    public static let transportModeKey = "NARU_LIVE_STIMULUS_TRANSPORT_MODE"
    public static let screenIndexKey = "NARU_LIVE_STIMULUS_SCREEN_INDEX"
    public static let originXKey = "NARU_LIVE_STIMULUS_X"
    public static let originYKey = "NARU_LIVE_STIMULUS_Y"

    public static let allowedLaunchEnvironmentKeys = [
        "PATH",
        "HOME",
        "TMPDIR",
        "USER",
        "LOGNAME",
        "SHELL",
        "__CF_USER_TEXT_ENCODING"
    ]

    public static let allowedPlacementEnvironmentKeys = [
        screenIndexKey,
        originXKey,
        originYKey
    ]

    public static func make(
        parent: [String: String],
        durationSeconds: String,
        frameIntervalSeconds: String,
        profileLabel: String,
        transportMode: String
    ) -> [String: String] {
        var environment = Dictionary(
            uniqueKeysWithValues: allowedLaunchEnvironmentKeys.compactMap { key in
                parent[key].map { (key, $0) }
            }
        )
        environment[durationKey] = durationSeconds
        environment[frameIntervalKey] = frameIntervalSeconds
        environment[profileLabelKey] = profileLabel
        environment[transportModeKey] = transportMode
        if let visualFreshnessFile = parent[BenchmarkVisualFreshnessSidecar.environmentKey],
           !visualFreshnessFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            environment[BenchmarkVisualFreshnessSidecar.environmentKey] = visualFreshnessFile
        }
        for key in allowedPlacementEnvironmentKeys {
            if let value = parent[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                environment[key] = value
            }
        }
        return environment
    }
}
