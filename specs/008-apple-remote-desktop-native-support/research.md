# Research: Apple Remote Desktop Native Support Strategy

## D1 - Treat Apple Screen Sharing as VNC-compatible, not full ARD admin

**Decision**: Naru should support macOS Remote Management / Apple Screen
Sharing through its public VNC-compatible path first. It should label this as
Apple Screen Sharing compatibility and explicitly avoid claiming full Apple
Remote Desktop administrator privileges.

**Rationale**:
- Apple documents that Remote Desktop can access computers running VNC software
  and that non-Apple VNC viewers can control Remote Desktop clients when the
  clients allow it.
- Apple also states that VNC access is similar to the Control command but does
  not grant other Remote Desktop administrator privileges beyond the currently
  logged-in user's privileges.
- This maps directly to Naru's existing VNC session model and can improve setup
  diagnostics without increasing protocol risk.

**Alternatives considered**:
- Claim full ARD support from a VNC login: rejected because administrator
  privileges, reporting, copy, power, and command features have separate
  privilege and protocol boundaries.
- Treat Apple hosts as generic VNC only: rejected because Apple setup,
  security, and extra-display behavior deserve first-class guidance.

**Source links**:
- https://support.apple.com/guide/remote-desktop/apde0dd523e/mac
- https://support.apple.com/guide/remote-desktop/apd84ce53cb/mac

## D2 - Default ports and display hints should follow Apple documentation

**Decision**: Apple Screen Sharing profiles should default to TCP `5900` for
control/observe and can suggest TCP `5901` and `5902` as additional display
ports. Diagnostics can also mention that High Performance screen sharing
requires UDP `5900`, `5901`, and `5902` readiness, but those UDP ports do not
make direct HPS support available in Naru by themselves.

**Rationale**:
- Apple's Remote Desktop port reference lists TCP `5900` for control/observe,
  UDP `5900` for send/share screen, TCP/UDP `3283` for reporting/additional
  data, and TCP `22` for SSH-tunneled encrypted functions.
- Apple's additional-display guidance says default, second, and third VNC
  displays can be addressed with ports `5900`, `5901`, and `5902`.
- Fixed port hints are useful diagnostics and do not expose user-specific data.

**Alternatives considered**:
- Blindly probe many ports: rejected for privacy, speed, and noisy diagnostics.
- Hide all port details: rejected because Apple display-port behavior is common
  setup friction.

**Source links**:
- https://support.apple.com/guide/remote-desktop/apd0c903fec/mac
- https://support.apple.com/guide/remote-desktop/apd5fcc5d03/mac

## D3 - High Performance screen sharing is research-only for now

**Decision**: Naru should not implement or advertise direct Apple High
Performance screen sharing as a selectable transport in this feature. It should
classify it as `researchOnly` and route users who want smoother visual transport
to Naru Helper Video.

**Rationale**:
- Apple documents High Performance screen sharing as supporting advanced color
  workflows, stereo audio, 4:4:4 chroma, HDR reference workflows, and 30/60fps.
- The documented requirements include Apple Silicon on both Macs, macOS Sonoma
  14 or later on both Macs, UDP `5900`, `5901`, and `5902`, one active HPS
  session per Mac, and high consistent bandwidth. Apple gives `75 Mbps` as the
  recommended bandwidth for a single 4K display.
- Naru is an iPhone/iPad app, and no public iOS client API is identified for
  directly joining this Apple-specific High Performance mode. Shipping a broken
  selector would hurt trust and distract from helper-video benchmarking.

**Alternatives considered**:
- Reverse engineer the protocol: rejected.
- Expose HPS as an advanced toggle: rejected until a public or licensed path is
  available and benchmarked.
- Use Naru Helper Video as the product-owned high-performance equivalent:
  accepted for the current performance roadmap.

**Source links**:
- https://support.apple.com/guide/remote-desktop/apdf8e09f5a9/mac

## D4 - ARD-class management actions should be helper-backed and approval gated

**Decision**: Naru may add ARD-class actions only through the optional paired
Naru Helper and only as fixed capabilities with explicit approval policies.
Initial candidates are system-status buckets, one-way user message, file
staging, keep-awake/wake readiness, lock-screen action, and power/session
actions. Shell command execution is deferred until a separate command/agent
approval spec.

**Rationale**:
- Apple Remote Desktop includes non-VNC management features: copy files, system
  status, sleep/wake/restart/log out, lock/unlock screen, messages/chat, and
  remote UNIX commands.
- Naru's constitution requires helper features to be optional, least-privilege,
  observable, and revocable. It also requires approval gates for sensitive or
  destructive actions.
- A helper-backed catalog keeps the feature product-aligned without pretending
  that VNC access grants ARD administrator privileges.

**Alternatives considered**:
- Add raw remote shell command execution immediately: rejected as too sensitive
  without a dedicated command approval and audit model.
- Implement management actions through VNC keystrokes/UI scripting: rejected as
  brittle and unsafe.
- Require the helper for Apple Screen Sharing profiles: rejected because basic
  VNC viewing must remain no-helper.

**Source links**:
- https://support.apple.com/guide/remote-desktop/apd18b6770c/mac
- https://support.apple.com/guide/remote-desktop/apd5535ee19/mac
- https://support.apple.com/guide/remote-desktop/apd37d6089c/mac
- https://support.apple.com/guide/remote-desktop/apd47b33625/mac
- https://support.apple.com/guide/remote-desktop/apd91b63ef0/mac
