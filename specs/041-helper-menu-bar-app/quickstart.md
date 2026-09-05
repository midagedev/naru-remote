# Quickstart: Naru Helper Menu Bar App

Founder runbook for the physical pass (spec 041). Sections 1–5 are the
person-facing checklist; section 6 is the release run that produces what
sections 1–2 consume. Expected outcome per the spec: download to first
paired handshake in under three minutes with no terminal opened.

## 1. Download and first launch

1. Download `Naru-Helper-<version>.zip` from
   [GitHub Releases](https://github.com/midagedev/naru-remote/releases/latest).
2. Unzip, move `Naru Helper.app` to `/Applications`, open it.
3. Expect: a menu bar icon, no Dock icon, no main window, and **no
   Gatekeeper refusal**. A block here means the artifact was not
   notarized — do not right-click-open past it; re-run the release
   (section 6).
4. Click the icon: the menu reads **Not paired**, both permissions read
   **Missing**, and the version matches the release tag. Missing on first
   launch is expected — the release bundle is a new identity
   (`com.naruremote.helper`), so grants older dev builds held do not carry
   over.

## 2. The two grants

From **Pair with iPhone…** (or the menu's permission lines), use **Open
System Settings** and grant each; the row flips to **Granted** without
relaunching:

- **System Settings → Privacy & Security → Accessibility** — text
  insertion.
- **System Settings → Privacy & Security → Screen Recording** — the video
  stream. If macOS asks to quit and reopen the app for the grant to take
  effect, do so.

## 3. Pair with the TestFlight app

1. On the Mac: **Pair with iPhone…** mints a fresh code and shows a QR.
   The offer is the same `naru://pair?code=…` bytes the CLI's `--pair`
   prints.
2. On the phone (the TestFlight build), open the pairing scan, point the
   camera at the QR, Save.
3. The window flips to **Paired** and dismisses the QR — a shown code is
   credential material and must not linger.
4. Connect from the phone's saved profile; type Korean through Compose
   and watch the video stream. The menu status should read **Connected**.

## 4. Reboot test

1. Turn on **Start at login**. If macOS reports the login item needs
   approval, approve it: **System Settings → General → Login Items**.
2. Reboot. Expect the icon back in the menu bar with no terminal and no
   Dock icon, and the phone's saved profile connecting with zero actions
   on the Mac.

## 5. Revoke test

1. **Revoke pairing…**, confirm.
2. The menu reads **Not paired**; the phone's next helper attempt is
   refused with the fixed revoked state; VNC viewing still works.
3. **Pair with iPhone…** again and re-save on the phone to restore the
   helper path.

## 6. Release run

```bash
scripts/release-naru-helper.sh --dry-run   # through the zip, no Apple calls
scripts/release-naru-helper.sh             # + notarize, staple, verify, record
scripts/release-naru-helper.sh --publish   # + GitHub Release upload
```

Credentials come from `~/.appstoreconnect` exactly as
`scripts/testflight-upload.sh` reads them; the script never echoes them.
After the real run, `artifacts/app-store/<YYYYMMDD>-helper-<version>/release.md`
must show:

- the version and build number, and the commit it was built from;
- the zip's sha256;
- notarization **Accepted**, with the submission id;
- passes for stapler validate, codesign `--verify --deep --strict`, and
  `spctl --assess -vv --type execute` (`source=Notarized Developer ID`).

It must contain no credential and no key id. If any of those lines is
missing or red, the release is not done — check the log paths the script
printed before publishing.

## Developer build

A Debug build run from Xcode, or the wrapper
`scripts/install-naru-helper-dev-app.sh` installs, is signed with the
Apple Development identity (or ad-hoc when no single Development identity
exists) — not Developer ID. macOS treats each identity as a different app
for TCC, so a developer build needs its own Accessibility and Screen
Recording grants, distinct from the release build's, and an ad-hoc rebuild
silently lapses its old grants. The menu's permission rows are where that
becomes visible instead of a mystery handshake failure. Benchmarks and CI
keep using the CLI with env-pinned secrets
(`NARU_HELPER_TOKEN=… .build/release/NaruHelper --listen --token-env NARU_HELPER_TOKEN …`),
which the app does not disturb — the two share only the pairing state
file under `~/.naru/`.
