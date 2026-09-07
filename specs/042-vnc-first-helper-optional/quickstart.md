# Quickstart: VNC-First, Helper-Optional Presentation

How to see each principle on a phone, and what "done" looks like.

## 1. VNC only, nothing about the helper

1. Fresh install (or delete every profile). The home shows **Add a
   Computer** as the one prominent button and a smaller "Add by QR (Naru
   Helper)" line marked optional.
2. Add a Mac by MagicDNS name / address, port 5900, Screen Sharing
   password. Connect.
3. The session shows no transport marker anywhere. Trackpad mode: one
   cursor.

## 2. Helper present, video live

1. Pair through the QR (scanner first line says the helper is optional;
   **Enter VNC details instead** is on the same screen).
2. Connect. A small `Helper` marker sits top-leading once video frames
   arrive. Pinch zooms; one cursor in trackpad mode.
3. On the Mac, `nettop -P -p $(pgrep -x screensharingd)` shows Screen
   Sharing's bytes out staying flat while the helper's bytes move.

## 3. Helper expected, fell back

1. On the Mac, remove the helper's Screen Recording grant (System
   Settings → Privacy & Security → Screen Recording) and relaunch it.
2. Connect from the phone. No marker; one line "Helper video off — Mac
   needs Screen Recording permission" appears once and can be dismissed.
   Tapping it opens the profile diagnostics.

## 4. Pin a profile to VNC

Profile editor → **Screen transport: VNC only**. Connect: no marker, no
notice, text bridge still works.

## Gates

```bash
swift test
xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  test -only-testing:NaruRemoteUITests/VncFirstScreenshotsUITests
```

Screenshots land in `artifacts/screenshots/vnc-first/`.
