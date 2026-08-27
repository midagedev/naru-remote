# Security Policy

Naru Remote carries VNC credentials and drives a remote computer, so a security
report here is worth taking seriously. Thank you for looking.

## Reporting a vulnerability

**Please do not open a public issue.**

Use GitHub's private reporting instead:
[**Report a vulnerability**](https://github.com/midagedev/naru-remote/security/advisories/new).
It is private to you and the maintainer until a fix ships.

If that is unavailable to you, reach [@midagedev](https://x.com/midagedev) and
ask for a private channel — without describing the issue in the message.

You should hear back within a few days. This is a one-person project, so please
allow a little slack, and expect the fix to arrive as a TestFlight build before
an App Store release.

## What is in scope

- Credential handling: Keychain storage, the `credentialRef` boundary, anything
  that could write a password into the profile file, a log, or a diagnostic
  export.
- The diagnostic export leaking anything outside its fixed catalogue — an
  address, a hostname, screen contents, or composed text.
- The RFB parsing path (`NaruRemote/Sources/NaruRemoteCore/VNC/`): a malicious
  or malformed server response causing memory unsafety, a crash loop, or
  unbounded allocation.
- Naru Helper's pairing and IPC boundary.
- Anything that sends data to a host the user did not name.

## What is not

- **VNC is not an encrypted protocol.** Naru is built for private networks —
  a tailnet, a LAN, a VPN — and the app warns explicitly before connecting to a
  public address. "Traffic is readable on a hostile network" is a property of
  VNC, not a vulnerability in this client. A way to *bypass* that warning is.
- A remote machine you have deliberately given control of doing what you told it
  to.
- Findings from an automated scanner with no demonstrated impact.

## Where the boundaries are written down

`.specify/memory/constitution.md` §IV states the security boundaries as product
rules, and each `specs/<n>-<slug>/spec.md` restates the ones its feature crosses.
If you find a place where the code and those documents disagree, that gap is
itself worth reporting.
