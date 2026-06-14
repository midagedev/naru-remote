# Physical iPad State Marker Smoke

Date: 2026-06-14

## Purpose

Add a repeatable connected-iPad gate that proves the launched app applied
safe seed profile and helper-video test state without relying on XCTest to
keep the application alive. The app writes the marker only when explicitly
launched with `NARU_TEST_WRITE_DEVICE_STATE_MARKER=1`.

## Privacy

The marker and reports do not include device identifiers, team IDs, profile
UUIDs, account IDs, hostnames, passwords, pairing tokens, frame pixels,
coordinates, exact timings, raw xcodebuild logs, or copied text.

## Evidence

- `bash -n scripts/run-naru-live-benchmark.sh`: passed.
- `scripts/run-naru-live-benchmark.sh physical-ipad-state-marker-smoke-self-test`: passed.
- `git diff --check`: passed.
- iPad simulator build:
  `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build`: passed.
- Simulator marker smoke: passed with `markerStatus=verified`.
- Connected physical iPad state-marker smoke:
  `deviceDiscoveryStatus=connected`, `deviceUnlockedSinceBootStatus=true`,
  `deviceBacklightState=activeOn`, `installStatus=passed`,
  `launchStatus=passed`, `runningStatus=passed`,
  `markerCopyStatus=failed`, `markerValidationLabel=missing`,
  `safeFailureLabel=stateMarkerNotVerified`.

## Provisioning Diagnosis

The physical app launch path can install and run the existing app bundle, but
the current non-interactive CLI build path cannot produce a fresh physical
device app bundle with the new marker hook. A safe provisioning inventory
showed:

- project `DEVELOPMENT_TEAM`: missing
- project provisioning profile specifier: missing
- shell/launchctl team environment: present
- local Apple Development identity count: one
- local provisioning profiles visible under the standard CLI inventory: zero
- bundle-matching profile count: zero

This separates the failure from app startup. The physical iPad is reachable and
the existing app stays running; the remaining action is to make xcodebuild see
a matching local provisioning profile for `com.naruremote.app` and the
connected iPad, or install a freshly built physical app from Xcode GUI and
rerun `physical-ipad-state-marker-smoke`.

## Next Action

After physical signing/provisioning is corrected, rerun:

```bash
scripts/run-naru-live-benchmark.sh physical-ipad-state-marker-smoke
```

Promotion requires `markerValidationLabel=passed` in addition to the existing
install, launch, and running labels.
