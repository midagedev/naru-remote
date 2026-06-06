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
- `lastFailureCode`: Optional fixed catalog value:
  - `authFailed`
  - `permissionMissing`
  - `codecUnsupported`
  - `streamStalled`
  - `decoderRejected`
  - `revoked`
  - `transportFailed`
  - `fallbackToVNC`
- `lastCheckedBucket`: Coarse recency bucket, not an exact timestamp.

Privacy:

- No helper endpoint, host name, token, display dimensions, frame count, byte
  count, exact timing, or frame content.

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
