public enum BenchmarkStreamShapeStimulusEnvironment {
    public static let commandKey = "NARU_LIVE_STIMULUS_COMMAND"
    public static let durationKey = "NARU_LIVE_STIMULUS_DURATION_SECONDS"
    public static let profileLabelKey = "NARU_LIVE_STIMULUS_PROFILE_LABEL"
    public static let transportModeKey = "NARU_LIVE_STIMULUS_TRANSPORT_MODE"

    public static let allowedLaunchEnvironmentKeys = [
        "PATH",
        "HOME",
        "TMPDIR",
        "USER",
        "LOGNAME",
        "SHELL",
        "__CF_USER_TEXT_ENCODING"
    ]

    public static func make(
        parent: [String: String],
        durationSeconds: String,
        profileLabel: String,
        transportMode: String
    ) -> [String: String] {
        var environment = Dictionary(
            uniqueKeysWithValues: allowedLaunchEnvironmentKeys.compactMap { key in
                parent[key].map { (key, $0) }
            }
        )
        environment[durationKey] = durationSeconds
        environment[profileLabelKey] = profileLabel
        environment[transportModeKey] = transportMode
        return environment
    }
}
