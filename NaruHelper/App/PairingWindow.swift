import NaruHelperKit
import NaruRemoteCore
import SwiftUI

/// The **Pair with iPhone…** surface (spec 041 FR-003/FR-004/FR-005).
/// The view owns no state beyond its confirmation alert; session
/// lifecycle — rotate on appear, retire on close and on the first
/// accepted handshake — lives in ``HelperAppModel``.
struct PairingWindow: View {
    @ObservedObject var model: HelperAppModel
    @State private var confirmsRegeneration = false

    var body: some View {
        Group {
            if model.pairingStatus == .connected {
                connectedView
            } else if model.pairingDisplay == .resolving {
                resolvingView
            } else if model.pairingDisplay == .noTailnetAddress {
                noTailnetAddressView
            } else {
                offerView
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .padding(24)
        .onAppear { model.pairingWindowAppeared() }
        .onDisappear { model.pairingWindowDisappeared() }
        .alert("Regenerate pairing code?", isPresented: $confirmsRegeneration) {
            Button("Regenerate", role: .destructive) { model.beginPairingSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Phones paired with the previous code will need to scan again.")
        }
    }

    // MARK: Offer

    private var offerView: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                qrCard
                SecureField("VNC password (optional)", text: $model.vncPassword)
                    .accessibilityIdentifier("vnc-password")
                Text("Included in this QR only. Never saved on the Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Regenerate QR") { confirmsRegeneration = true }
                        .accessibilityIdentifier("regenerate-qr")
                    Spacer()
                    Button("Copy code") { model.copyOfferCode() }
                        .accessibilityIdentifier("copy-code")
                }
            }
            .frame(width: 344)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text("Scan with Naru Remote on your iPhone, or with the Camera app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                PermissionRow(
                    identifier: "permission-accessibility",
                    title: "Accessibility",
                    status: model.accessibility
                ) {
                    model.openPermissionSettings(.accessibility)
                }
                PermissionRow(
                    identifier: "permission-screen-recording",
                    title: "Screen Recording",
                    status: model.screenRecording
                ) {
                    model.openPermissionSettings(.screenRecording)
                }
                Divider()
                listenerRow(
                    identifier: "listener-text",
                    label: "Text bridge \(naruHelperTextBridgeDefaultPort)",
                    state: model.textListenerState)
                listenerRow(
                    identifier: "listener-video",
                    label: "Video \(naruHelperVideoStreamDefaultPort)",
                    state: model.videoListenerState)
                Spacer()
            }
            .frame(minWidth: 280, alignment: .leading)
        }
    }

    /// The QR at ≥ 320 pt on a white 12-pt padded card. The Kit bakes the
    /// four-module quiet zone into the image; the card adds display
    /// margin so the code never touches an edge.
    @ViewBuilder
    private var qrCard: some View {
        if let qr = model.displayedQRImage {
            // Resizable to exactly 320 pt: the Kit's image is ≥ 320 px and
            // its exact size depends on the module count, so drawing it at
            // native size overflowed the 344-pt column (vision round 3).
            Image(decorative: qr, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: 320, height: 320)
                .padding(12)
                .background(Color.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pairing QR code")
                .accessibilityIdentifier("pairing-qr")
        } else {
            // A session exists (host info present) but no image rendered —
            // keep the layout stable rather than shifting the columns.
            Color.white
                .frame(width: 344, height: 344)
        }
    }

    private func listenerRow(
        identifier: String,
        label: String,
        state: NaruHelperListenerState
    ) -> some View {
        Text("\(label): \(state.rowLabel)")
            .accessibilityIdentifier(identifier)
    }

    // MARK: Resolving

    private var resolvingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Preparing the pairing code…")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pairing-resolving")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: No tailnet address

    private var noTailnetAddressView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("This Mac has no Tailscale address. Connect it to your tailnet and retry.")
                .multilineTextAlignment(.center)
            Button("Retry") { model.beginPairingSession() }
                .accessibilityIdentifier("retry-tailnet")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Connected

    private var connectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Paired — iPhone connected")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("paired-headline")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One Accessibility / Screen Recording row: the fixed-catalog verdict
/// plus the one-click route to the matching System Settings pane.
private struct PermissionRow: View {
    let identifier: String
    let title: String
    let status: NaruHelperPermissionStatus
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize()
                    .accessibilityIdentifier("\(identifier)-title")
                Text(status.rowLabel)
                    .foregroundStyle(status == .granted ? .secondary : .primary)
                    .fixedSize()
                    .accessibilityIdentifier("\(identifier)-state")
            }
            Spacer(minLength: 12)
            Button("Open Settings…", action: openSettings)
                .fixedSize()
                .accessibilityIdentifier("\(identifier)-settings")
        }
    }
}
