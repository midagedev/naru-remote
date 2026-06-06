# Data Model: Host Helper Video Stream

## HelperVideoProfileState

Per saved profile, non-secret state that controls whether helper video can be
attempted.

Fields:

- `enabled`: Boolean opt-in. Defaults to false.
- `pairingFingerprint`: Non-secret, one-way fingerprint for the paired helper.
  It is not an endpoint, host identity, auth token, auth proof, or stable
  public device identifier.
- `availability`: Fixed catalog value:
  - `notConfigured`
  - `disabled`
  - `checking`
  - `available`
  - `permissionMissing`
  - `codecUnsupported`
  - `revoked`
  - `unreachable`
  - `failed`
  - `privateNetworkRequired`
- `lastFailureCode`: Optional fixed catalog value:
  - `notConfigured`
  - `disabled`
  - `authFailed`
  - `permissionMissing`
  - `codecUnsupported`
  - `streamStalled`
  - `decoderRejected`
  - `revoked`
  - `transportFailed`
  - `fallbackToVNC`
  - `privateNetworkRequired`
- `lastCheckedBucket`: Coarse recency bucket, not an exact timestamp.

Privacy:

- No helper endpoint, host name, token, display dimensions, frame count, byte
  count, exact timing, or frame content.

## HelperVideoConnectionConfiguration

Per saved profile, non-secret opt-in configuration for whether the app may
attempt helper video later.

Fields:

- `isEnabled`: Boolean opt-in. Defaults to false.
- `isRevoked`: Boolean revocation marker. Defaults to false. When true, the
  profile must not keep `pairingSecretRef` or `pairingFingerprint`.
- `pairingSecretRef`: Reference to a device-local credential store entry. The
  secret itself is never stored in the profile JSON.
- `pairingFingerprint`: Non-secret fingerprint for the paired helper.

Rules:

- A profile whose `hostKind` is `advancedManualPublicEndpoint` must publish
  `privateNetworkRequired` helper-video state and must not attempt helper
  video.
- A missing configuration keeps the VNC-only baseline.
- Disabled or revoked helper-video state keeps VNC connected and available for
  all visual, input, clipboard, diagnostic, reconnect, and fallback behavior.

Privacy:

- No helper endpoint, host name, auth token, display dimensions, frame content,
  byte counts, coordinates, or exact timing.

## HelperVideoAuthProof

Per-message authentication proof for helper-video client requests.

Fields:

- `scheme`: Fixed `hmac-sha256` prefix in the serialized proof.
- `requestID`: Included in the signed canonical message.
- `messageType`: Included in the signed canonical message.
- `profileFingerprint`: Included in the signed canonical message.

Rules:

- The pairing secret is used only as local HMAC key material and is never
  serialized into helper-video envelopes.
- `authProof` is present only on app-to-helper request envelopes.
- Helper responses must omit `authProof`.
- `authProof` authenticates the request but does not encrypt the JSON body or
  any future binary access-unit payload.

Privacy:

- `authProof`, pairing secrets, endpoints, host names, frame payloads, and
  exact timing samples are not diagnostic-safe.

## NaruHelperVideoCaptureCapabilityResponse

Safe macOS helper response for the ScreenCaptureKit capture probe.

Fields:

- `schemaVersion`: Integer contract version.
- `availability`: Fixed `HelperVideoAvailability` label.
- `screenRecordingPermission`: Fixed label:
  - `granted`
  - `missing`
  - `unsupported`
- `captureSourceState`: Fixed label:
  - `notChecked`
  - `available`
  - `unavailable`
  - `unsupported`
- `captureAPI`: Optional fixed label, initially `screenCaptureKit`.
- `safeFailureCode`: Optional fixed helper-video failure code.

Rules:

- Missing Screen Recording permission reports `permissionMissing` and does not
  query shareable screen content.
- Granted permission may query ScreenCaptureKit shareable content, but reports
  only a fixed availability state.

Privacy:

- No display identifiers, display names, window names, dimensions, frame
  content, endpoints, host names, byte counts, exact timings, or OS error text.

## NaruHelperVideoEncoderPrototypeResponse

Safe macOS helper response for the gated VideoToolbox H.264 encoder prototype.

Fields:

- `schemaVersion`: Integer contract version.
- `availability`: Fixed `HelperVideoAvailability` label.
- `featureFlagState`: Fixed label:
  - `enabled`
  - `disabled`
- `encoderAPI`: Optional fixed label, initially `videoToolbox`.
- `codec`: Fixed label, initially `h264`.
- `codecProfile`: Fixed label, initially `high` for the low-latency prototype.
- `latencyMode`: Fixed label, initially `lowLatency`.
- `qualityBucket`: Fixed label, initially `readability`.
- `sessionState`: Fixed label:
  - `notStarted`
  - `prepared`
  - `unavailable`
  - `unsupported`
- `safeFailureCode`: Optional fixed helper-video failure code.

Rules:

- The prototype is inactive unless `NARU_HELPER_VIDEO_ENCODER_PROTOTYPE` is set
  to an explicit enabled value.
- When disabled, the helper reports `disabled` and does not create a
  VideoToolbox compression session.
- When enabled, the helper creates and prepares a synthetic H.264 compression
  session only; it does not capture, emit, log, or persist encoded frames.

Privacy:

- No display identifiers, display names, window names, dimensions, frame
  content, endpoints, host names, byte counts, exact timings, payloads, or OS
  error text.

## HelperVideoStreamDescriptor

Safe stream metadata exchanged after authentication.

Fields:

- `protocolVersion`: Integer.
- `codec`: Fixed label, initially `h264`.
- `codecProfile`: Fixed label such as `baseline`, `main`, `high`, or
  `unknown`.
- `latencyMode`: Fixed label such as `lowLatency` or `balanced`.
- `qualityBucket`: Fixed label such as `readability`, `balanced`, or
  `fidelity`.
- `frameRateBucket`: Fixed label such as `upTo15`, `upTo30`, or `unknown`.
- `colorMode`: Fixed label such as `standardDynamicRange` or `unknown`.
- `supportsKeyframeRequest`: Boolean.
- `supportsFallbackSignal`: Boolean.

Privacy:

- No width, height, display id, display name, endpoint, byte counts, or exact
  timestamps.

## HelperVideoStreamHealth

Runtime health state used by the app and benchmark gate.

Fields:

- `state`: Fixed label:
  - `idle`
  - `starting`
  - `healthy`
  - `stalled`
  - `fallbackToVNC`
  - `ended`
  - `failed`
- `startupBand`: Fixed label:
  - `notMeasured`
  - `fast`
  - `usable`
  - `slow`
  - `failed`
- `sustainedUpdateBand`: Fixed label:
  - `notMeasured`
  - `smooth`
  - `usable`
  - `choppy`
  - `stalled`
- `decodePressure`: Fixed label:
  - `notMeasured`
  - `low`
  - `medium`
  - `high`
- `fallbackCountBucket`: Fixed label:
  - `none`
  - `one`
  - `few`
  - `many`

Privacy:

- Coarse buckets only. No exact per-frame timing, frame count, pixel content,
  dimensions, byte counters, or endpoint details.

## HelperVideoAccessUnit

In-memory transport payload for one encoded unit.

Fields:

- `sequence`: Monotonic process-local sequence number.
- `kind`: `parameterSet`, `keyframe`, `delta`, or `endOfStream`.
- `payload`: Encoded bytes.

Privacy:

- This value must not be logged, persisted, attached to diagnostics, or
  exported in benchmark artifacts.
