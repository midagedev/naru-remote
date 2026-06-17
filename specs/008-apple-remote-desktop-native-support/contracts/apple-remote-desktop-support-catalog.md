# Contract: Apple Remote Desktop Support Catalog

## Purpose

The catalog tells the app, diagnostics, and helper which Apple Remote
Desktop-related capabilities are safe to present.

It is intentionally product-level. It does not define or reverse engineer Apple
private protocols.

## Support Tier Values

```json
{
  "schemaVersion": 1,
  "capabilities": [
    {
      "capabilityID": "appleScreenSharing.vncControlObserve",
      "tier": "vncCompatible",
      "defaultPort": 5900,
      "safeSetupLabels": [
        "enableRemoteManagement",
        "allowVNCViewers",
        "usePrivateNetwork",
        "fullARDAdminUnavailableThroughVNC"
      ]
    },
    {
      "capabilityID": "appleScreenSharing.additionalDisplays",
      "tier": "vncCompatible",
      "candidatePorts": [5901, 5902],
      "safeSetupLabels": [
        "selectDisplayPort"
      ]
    },
    {
      "capabilityID": "appleRemoteDesktop.systemStatus",
      "tier": "helperBacked",
      "requiresApproval": false,
      "safeResultLabelsOnly": true
    },
    {
      "capabilityID": "appleRemoteDesktop.messageUser",
      "tier": "helperBacked",
      "requiresApproval": true,
      "safeResultLabelsOnly": true
    },
    {
      "capabilityID": "appleRemoteDesktop.highPerformanceScreenSharing",
      "tier": "researchOnly",
      "safeSetupLabels": [
        "appleSiliconRequired",
        "macOSSonomaRequired",
        "udp5900To5902Required",
        "highBandwidthRequired",
        "useNaruHelperVideo"
      ]
    }
  ]
}
```

## Privacy Rules

Catalog reports may expose:

- fixed capability IDs
- fixed tier labels
- fixed port numbers from Apple documentation
- fixed setup labels
- pass/fail/disabled states

Catalog reports must not expose:

- hostnames or endpoint values
- credentials
- raw VNC or helper payloads
- message text
- shell command text
- file paths or filenames
- usernames
- screenshots, pixels, or coordinates
- exact timing series
