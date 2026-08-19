# Runbook: ship a build to TestFlight

One command:

```bash
scripts/testflight-upload.sh --bump
```

That runs the fast gates, takes the next build number, archives Release for
device, **verifies the archive against the submission contract**, exports a
signed App Store build, validates it, uploads it, and waits for Apple to finish
processing. It finishes by writing `artifacts/app-store/<date>-build<N>/upload.md`.

Other modes:

| Command | Use |
| --- | --- |
| `scripts/testflight-upload.sh` | ship the build number already in `project.yml` |
| `scripts/testflight-upload.sh --dry-run` | archive + verify + validate, stop before upload |
| `scripts/testflight-upload.sh --status` | what does App Store Connect hold for this version? |
| `--allow-dirty` | ship an uncommitted tree (records "dirty tree" in the receipt) |
| `--no-gates` | skip `swift test` (only when you just ran it) |

## One-time setup on a new machine

Credentials never enter the repo. Two files, both private, both outside it:

```
~/.appstoreconnect/credentials.env                     # 0600
~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8     # 0600, from App Store Connect
```

`credentials.env`:

```sh
ASC_KEY_ID=<the key id, which is also in the .p8 filename>
ASC_ISSUER_ID=<the issuer id from App Store Connect → Users and Access → Integrations>
```

```bash
chmod 700 ~/.appstoreconnect ~/.appstoreconnect/private_keys
chmod 600 ~/.appstoreconnect/credentials.env ~/.appstoreconnect/private_keys/*.p8
scripts/testflight-upload.sh --status   # proves the key, the issuer and the API path
```

Override the locations with `ASC_CREDENTIALS_FILE` / `ASC_PRIVATE_KEY` if a
machine keeps them elsewhere. The API key needs the **App Manager** role to
upload.

`altool` takes the key id and issuer as command-line arguments — Apple's
interface, not a choice — so they are visible in this machine's process list
while an upload runs. Nothing in the repo, the logs or the receipt records
them.

## What the script verifies before it uploads

Each check is here because it has gone wrong, or because Apple would only tell
you after a full upload:

| Check | Why |
| --- | --- |
| build number not already upstream | App Store Connect rejects a duplicate *after* the archive and upload; asking the API first costs a second |
| `CFBundleShortVersionString` / `CFBundleVersion` match `project.yml` | the archive is the thing shipped; the manifest is the thing reviewed |
| `CFBundleIdentifier` = `com.naruremote.app`, signing team = `XEF9KH7N43` | a wrong identity uploads to nothing |
| `MinimumOSVersion` 17.0 | the deployment target the specs assume |
| `ITSAppUsesNonExemptEncryption=false` | without it the build parks in "Missing Compliance" and never reaches a tester |
| `PrivacyInfo.xcprivacy` in the bundle | required manifest; easy to lose when the app target's sources move |
| no `NARU_TEST_*` strings in the Release binary | the store-capture fixtures and test hooks are DEBUG-only; one leaking into a shipped binary would let a tester drive a fake session |

A failed check aborts before anything is uploaded.

## Account-owner steps the script cannot do

These are web actions in App Store Connect, and they are the founder's:

1. **Assign the build to the internal tester group** (TestFlight → Internal
   Testing). A processed build is not visible to testers until it is assigned.
2. **Export compliance**, if prompted the first time on a version.
3. **For a public release**: store screenshots upload, EU DSA trader declaration,
   Korea declarations, and submit for review — see `SUBMISSION_READINESS.md` §5.5.

## When it fails

- **`build N ... already exists upstream`** — re-run with `--bump`.
- **archive/export failure** — the full log path is printed; automatic signing
  needs the Apple ID in Xcode to still be authorised (`-allowProvisioningUpdates`
  cannot fix an expired session).
- **`processingState=FAILED|INVALID`** — Apple rejected it after upload; the
  reason is in App Store Connect (usually an asset or entitlement).
- **still `PROCESSING` after 30 minutes** — normal for a first upload on a
  version; check later with `--status`.
