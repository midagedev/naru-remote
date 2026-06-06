# Helper Video Fake Transport Comparison Summary

Date: 2026-06-06 KST

## Purpose

Record the benchmark report shape for comparing the existing VNC visual path
with a future helper-video visual path before running a live helper stream.

## Evidence

```bash
swift test --filter BenchmarkVisualTransport
```

Result: 7 selected tests passed.

No live target was contacted for this artifact. No live credential, endpoint,
host name, port value, frame content, byte count, display dimension, coordinate,
token, or exact helper timing is included.

## Comparison Shape

```json
{
  "visualTransportComparison": {
    "schemaVersion": 1,
    "selectedVisualTransports": [
      "vnc",
      "helper-video"
    ],
    "vncReportShape": "existing-live-benchmark-report",
    "helperVideoReports": [
      {
        "schemaVersion": 1,
        "visualTransport": "helper-video",
        "streamProtocolVersion": 1,
        "codec": "h264",
        "codecProfile": "unknown",
        "latencyMode": "lowLatency",
        "qualityBucket": "readability",
        "frameRateBucket": "upTo30",
        "colorMode": "standardDynamicRange",
        "supportsKeyframeRequest": true,
        "supportsFallbackSignal": true,
        "streamState": "idle",
        "startupBand": "notMeasured",
        "sustainedUpdateBand": "notMeasured",
        "decodePressure": "notMeasured",
        "fallbackCountBucket": "none",
        "verdict": "disabled",
        "issueCodes": [
          "helper-video-stream-disabled"
        ]
      }
    ]
  }
}
```

## Interpretation

- `vncReportShape` means the existing `VNCLiveBenchmark` report remains the VNC
  baseline envelope.
- `helperVideoReports` is intentionally disabled until the fake helper stream
  and later live helper stream provide aggregate startup, sustained update,
  decode/render pressure, and fallback buckets.
- The fixed issue code is a promotion blocker, not a runtime error.
