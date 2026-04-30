# Contract: Connection Diagnostics

## Purpose

Define the user-visible diagnostic stages for Naru Remote MVP. This is a product
contract, not a concrete API schema.

## Stage Order

1. `dns`
2. `tcp`
3. `rfbHandshake`
4. `authentication`
5. `firstFrame`
6. `clipboardText`

## Stage Result

Each stage produces:

- `stage`: one of the stage names above
- `status`: `notStarted`, `running`, `passed`, `failed`, `skipped`
- `safeTitle`: short user-facing label
- `safeDetail`: short explanation safe for diagnostic export
- `nextAction`: optional user action
- `timestamp`

## Privacy Rule

Diagnostic output must not include:

- VNC passwords or credential tokens
- Local composed text
- Framebuffer screenshots
- Full raw clipboard payloads

Default exports include stage, status, and title only. Explicit detail exports
must use a fixed safe detail catalog by stage, not caller-provided `safeDetail`
or `nextAction` strings. Raw next actions are not exported by the MVP diagnostic
export API.

## Example User-Safe Messages

- `MagicDNS did not resolve this host. Check Tailscale and the host name.`
- `Host reached, but port 5900 is closed.`
- `VNC service responded with an unsupported handshake.`
- `Authentication failed. Check the VNC password.`
- `Connected, but no frame arrived yet.`
- `Text clipboard is unavailable for this server.`
