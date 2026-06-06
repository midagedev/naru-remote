# Tight-First Cursor Depth Sweep Summary - 2026-06-07

## Goal

`tight-first-cursor` is the current trackpad-friendly VNC benchmark candidate,
but longer 10-second runs still show p95 update warnings dominated by
server/network first-byte wait. This sweep checks whether request/response
pipeline depth 2 or 3 improves sustained usability enough to justify product
work.

## Change

Added `scripts/run-naru-live-benchmark.sh
bounded-vnc-tight-cursor-depth-sweep`.

The mode:

- imports live host/password only from the current shell or `launchctl`;
- builds `VNCLiveBenchmark` once;
- runs fixed `tight-first-cursor` at request pipeline depths 1, 2, and 3;
- uses 12 stream-shape samples over a 10-second sustained window per depth;
- keeps app-like 60 Hz request pacing, normal power, app client-pressure mode,
  and the external controlled stimulus;
- rejects caller overrides for managed benchmark dimensions, including profile,
  transport, request pipeline depth, timing, samples, progress file, help, and
  JSON flags;
- emits only a top-level safe JSON wrapper, per-depth safe wrappers, and
  benchmark JSON reports.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh --help \
  | rg "bounded-vnc-tight-cursor-depth-sweep"
scripts/run-naru-live-benchmark.sh bounded-vnc-tight-cursor-depth-sweep \
  -- --stream-shape-request-pipeline-depth 2
scripts/run-naru-live-benchmark.sh bounded-vnc-tight-cursor-depth-sweep \
  -- --stream-shape-profiles tight-first
scripts/run-naru-live-benchmark.sh bounded-vnc-tight-cursor-depth-sweep
```

Live safe-field result:

```json
{"schemaVersion":1,"mode":"bounded-vnc-tight-cursor-depth-sweep","status":"completed","profileLabel":"tight-first-cursor","depths":[{"depth":1,"status":"passed","verdict":"warning","primaryConstraint":"receivePath","primaryIssueCode":"p95-update-warning","contentUpdateSamples":11,"receivedSamples":12,"contentFPS":9.009009009009008,"averageUpdateMS":78,"maxP95UpdateMS":482,"maxClientProcessingP95MS":2,"firstByteWaitSharePermille":1000,"rendererFullUploadPermille":0},{"depth":2,"status":"passed","verdict":"warning","primaryConstraint":"receivePath","primaryIssueCode":"p95-update-warning","contentUpdateSamples":10,"receivedSamples":12,"contentFPS":6.8212824010914055,"averageUpdateMS":96,"maxP95UpdateMS":474,"maxClientProcessingP95MS":2,"firstByteWaitSharePermille":1000,"rendererFullUploadPermille":0},{"depth":3,"status":"passed","verdict":"fail","primaryConstraint":"clientDecode","primaryIssueCode":"client-processing-failed","contentUpdateSamples":10,"receivedSamples":12,"contentFPS":6.293266205160479,"averageUpdateMS":106,"maxP95UpdateMS":489,"maxClientProcessingP95MS":128,"firstByteWaitSharePermille":998,"rendererFullUploadPermille":0}]}
```

## Interpretation

Do not promote request pipeline depth 2 or 3 for the product stream loop.

- Depth 1 remains the best sustained candidate in this controlled run: 11/12
  content samples, 9.01 content FPS, 78 ms average update, and 2 ms max
  client-processing p95. It still warns on p95 update tail at 482 ms.
- Depth 2 does not improve the run: 10/12 content samples, 6.82 content FPS,
  96 ms average update, and p95 still near 474 ms.
- Depth 3 fails by client-processing pressure: 128 ms max client-processing
  p95.

The first-byte wait share stays at roughly 1000 permille for all depths, so the
remaining p95 tail is server/network response timing rather than client decode
or renderer upload. Keep `tight-first-cursor` as the current app opt-in
candidate, but keep request pipeline depth at 1 until a stronger transport
change or server-side strategy is available.

## Privacy

This artifact contains only fixed mode/profile labels, fixed verdict/issue
labels, depth integers, aggregate counts, permille ratios, and aggregate timing
values. It does not include host identity, credentials, ports, executable paths,
command lines, raw stdout/stderr, TCP/RFB errors, request coordinates,
dimensions, pixels, byte counts, stimulus command text, draft text, marked
text, or IME state.
