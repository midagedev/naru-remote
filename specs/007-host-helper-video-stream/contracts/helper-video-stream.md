# Contract: Helper Video Stream

This contract is a first implementation target for a private-network,
authenticated helper video stream. It is intentionally smaller than a full
remote desktop protocol. VNC remains the control and fallback channel.

## Transport

- One authenticated helper-video session per active Naru Remote profile.
- Private-network endpoint only.
- Reuse the helper pairing secret model from `006-host-helper-text-bridge`.
- Length-prefixed messages:
  - 4-byte big-endian JSON length
  - UTF-8 JSON envelope
  - for `videoAccessUnit` only: 4-byte big-endian binary payload length
    followed by exactly that many encoded bytes
- No newline-delimited framing.

## Message Envelope

```json
{
  "schemaVersion": 1,
  "requestID": "uuid",
  "messageType": "startStream",
  "profileFingerprint": "sha256:...",
  "authProof": "redacted-in-diagnostics",
  "body": {}
}
```

Diagnostics may include `schemaVersion`, `messageType`, and fixed result
labels. Diagnostics must not include `authProof`, endpoint, host name, display
name, dimensions, raw payload, or exact timestamps.

## Message Types

### `capabilityRequest`

App asks whether helper video can run.

Response body:

```json
{
  "availability": "available",
  "screenRecordingPermission": "granted",
  "codecSupport": "h264",
  "latencyModes": ["lowLatency", "balanced"]
}
```

All values are fixed catalog labels.

### `startStream`

App requests a visual-only helper video stream.

Request body:

```json
{
  "codec": "h264",
  "latencyMode": "lowLatency",
  "qualityBucket": "readability",
  "maxFrameRateBucket": "upTo30"
}
```

Response body:

```json
{
  "result": "accepted",
  "streamDescriptor": {
    "protocolVersion": 1,
    "codec": "h264",
    "codecProfile": "unknown",
    "latencyMode": "lowLatency",
    "qualityBucket": "readability",
    "frameRateBucket": "upTo30",
    "colorMode": "standardDynamicRange",
    "supportsKeyframeRequest": true,
    "supportsFallbackSignal": true
  }
}
```

### `videoAccessUnit`

Helper sends one encoded access unit. This message is never diagnostic-safe.

Envelope body:

```json
{
  "sequence": 42,
  "kind": "keyframe"
}
```

The binary payload follows the JSON body in the framed message format chosen by
the implementation task: JSON length, JSON envelope, binary length, then binary
payload. The payload must never be logged or persisted.

### `requestKeyframe`

App asks the helper to send the next available keyframe.

Body:

```json
{
  "reason": "decoderRecovery"
}
```

### `streamStalled`

Helper reports that the helper-video visual path is no longer producing usable
updates. The app must keep VNC connected and return the visual path to VNC.

Body:

```json
{
  "reason": "noAccessUnit",
  "health": {
    "state": "stalled",
    "startupBand": "usable",
    "sustainedUpdateBand": "stalled",
    "decodePressure": "medium",
    "fallbackCountBucket": "one"
  }
}
```

All values are fixed catalog labels or coarse buckets; no frame, byte count,
endpoint, coordinate, dimension, or exact timing data is allowed.

### `stopStream`

App stops helper video and returns to VNC visual path.

Body:

```json
{
  "reason": "userDisabled"
}
```

## Fixed Failure Codes

- `authFailed`
- `permissionMissing`
- `codecUnsupported`
- `streamStalled`
- `decoderRejected`
- `transportFailed`
- `revoked`
- `fallbackToVNC`

## Privacy Rules

Never export or log:

- Encoded or decoded frames
- Screenshots or thumbnails
- Display dimensions, display IDs, or display names
- Coordinates
- Byte counts
- Endpoint addresses
- Auth tokens or proofs
- Host names
- Exact per-frame timing samples
- Compose text or clipboard contents
