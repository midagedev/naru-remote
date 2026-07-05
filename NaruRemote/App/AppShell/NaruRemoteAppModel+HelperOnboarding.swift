import Foundation
import NaruRemoteCore

/// Helper-onboarding (spec 010) support built entirely on the app
/// model's **existing public surface**, so it needs no change to
/// `NaruRemoteAppModel.swift`.
///
/// The verify step's in-flow helper-handshake test wants a
/// single-profile, awaitable reachability check. The only public
/// trigger today is `refreshProfileReachability()` (fire-and-forget,
/// all profiles) whose results land on the published
/// `helperTextBridgeState`. This wraps that pair into an awaitable
/// single-profile result by triggering a refresh and polling the
/// published state until the profile's availability settles out of
/// `.checking` (or a bounded timeout elapses).
///
/// This is intentionally not called from the shipped verify path yet:
/// the app shell passes the profile editor only closures, so the shell
/// must forward this as `onTestHelper` to reach the view (spec 010 plan
/// "Named API Gap"). A cleaner future refinement is a real
/// single-profile probe on the model backed by the private
/// `probeHelperTextBridge`, replacing this refresh+poll.
extension NaruRemoteAppModel {
    public func testHelperTextBridge(
        for profileID: ConnectionProfile.ID,
        pollInterval: Duration = .milliseconds(150),
        timeout: Duration = .seconds(12)
    ) async -> HelperTextBridgeProfileState {
        refreshProfileReachability()

        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if Task.isCancelled { break }
            if let state = helperTextBridgeState[profileID],
               state.availability != .checking {
                return state
            }
            try? await Task.sleep(for: pollInterval)
        }
        return helperTextBridgeState[profileID] ?? HelperTextBridgeProfileState()
    }
}
