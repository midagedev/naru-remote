# Helper Video Profile Guard Summary

Date: 2026-06-06 KST

## Decision

Helper video remains optional and private-network only before any helper capture
prototype is promoted. Saved profiles may now carry a helper-video opt-in
configuration, but public-host profiles publish a fixed `privateNetworkRequired`
state and helper-video selection refuses to start.

## Evidence

```bash
swift test --filter 'ConnectionProfileTests|HelperVideoTests|NaruRemoteAppModelTests/testNoHelperVideo|NaruRemoteAppModelTests/testPublicHostProfileBlocksHelperVideo|NaruRemoteAppModelTests/testStoredHelperVideo|NaruRemoteAppModelTests/testStoredPublicHostHelperVideo|NaruRemoteAppModelTests/testDisableAndRevokeHelperVideo'
```

Result: 16 selected tests passed before review follow-up.

Review follow-up adds helper-video preference reload coverage:

```bash
swift test --filter 'ConnectionProfileTests|NaruRemoteAppModelTests/testDisableAndRevokeHelperVideo|NaruRemoteAppModelTests/testRevokeHelperVideoKeepsCredentialWhenProfilePersistenceFails'
```

Result: 9 selected tests passed.

Updated targeted verification:

```bash
swift test --filter 'ConnectionProfileTests|HelperVideoTests|NaruRemoteAppModelTests/testNoHelperVideo|NaruRemoteAppModelTests/testPublicHostProfileBlocksHelperVideo|NaruRemoteAppModelTests/testStoredHelperVideo|NaruRemoteAppModelTests/testStoredPublicHostHelperVideo|NaruRemoteAppModelTests/testDisableAndRevokeHelperVideo|NaruRemoteAppModelTests/testRevokeHelperVideoKeepsCredentialWhenProfilePersistenceFails'
```

Result: 20 selected tests passed.

## Safety Boundary

- No helper endpoint, host name, token, password, frame content, byte count,
  coordinate, display dimension, or exact timing is stored in the helper-video
  profile configuration.
- No-helper VNC profiles continue to report `notConfigured` helper-video state
  and stay on the VNC framebuffer path.
- Disabled and revoked helper-video states are stored on the profile and fall
  back to VNC without clearing the active session or Compose draft.
- Revoked helper-video credential refs are deleted only after profile storage
  succeeds, avoiding a profile JSON / credential-store mismatch on write
  failure.
- Public-host profiles use fixed `privateNetworkRequired` labels rather than
  attempting helper video.
