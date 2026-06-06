# Helper Video Auth Transport Summary

Date: 2026-06-06

## Scope

This PR implements the authenticated helper-video transport message slice. It
adds HMAC-SHA256 `authProof` generation and verification for app-to-helper
request envelopes, capability/start-stream frame handlers in the macOS helper
kit, and shared authorization for keyframe and stop-stream request envelopes.

It does not open a live helper-video listener, capture screen frames, send
encoded access units, decode video on iOS, or change VNC visual defaults.

## Evidence

```bash
swift test --filter NaruHelperVideoTransport
```

Result: 9 selected tests passed.

The tests verify:

- Auth proofs are scoped to request ID, message type, profile fingerprint, and
  pairing secret.
- Invalid proofs reject capability requests without calling the provider.
- Revoked pairings reject start-stream requests.
- Authenticated capability and start-stream frames round-trip through the
  helper-video length-prefixed wire codec.
- Response JSON omits `authProof`, pairing secrets, payloads, endpoints, host
  names, display names, dimensions, and byte-count labels.

## Safety Boundary

- Request authentication does not encrypt the JSON body or future binary access
  unit payloads.
- Helper responses omit `authProof`.
- Raw pairing secrets remain local key material and are never serialized into
  helper-video envelopes.
- This slice handles typed messages only; live streaming and binary payload
  transport remain separate follow-up work.

## Next Work

- Add a live helper-video listener/transport loop for authenticated capability
  and stream-start requests.
- Add access-unit payload transport without logging or persisting encoded bytes.
- Add iOS decode/display prototype and constrained-cellular comparison once the
  live helper-video stream exists.
