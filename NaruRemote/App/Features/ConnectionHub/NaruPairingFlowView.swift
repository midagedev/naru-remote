import NaruRemoteCore
import SwiftUI

#if os(iOS) && canImport(UIKit)
import AVFoundation
#endif

/// QR pairing flow (spec 040): the scan surface and the confirmation
/// sheet both decode through `NaruPairingOfferWire` — the same parser the
/// `naru://` deep link uses — so all three doors (in-app scanner, system
/// camera, paste) accept identical input (FR-001/FR-006).
///
/// Secrets ride the offer only in transit: the confirm sheet hands them
/// to the app model's existing Keychain save path and never persists
/// them into view state beyond the sheet's lifetime (FR-004).

// MARK: - Scan

public struct NaruPairingScanView: View {
    @Environment(\.dismiss) private var dismiss
    private let onDecoded: @MainActor (NaruPairingOffer) -> Void

    @State private var pastedCode = ""
    @State private var failureMessage: String?
    @State private var didDeliver = false
    #if os(iOS) && canImport(UIKit)
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    #endif

    public init(onDecoded: @escaping @MainActor (NaruPairingOffer) -> Void) {
        self.onDecoded = onDecoded
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    #if os(iOS) && canImport(UIKit)
                    if cameraPermission == .authorized {
                        NaruPairingCodeScanner(
                            onCode: { deliver($0) }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(NaruColors.hairline, lineWidth: 1)
                        )
                        .accessibilityIdentifier("naru.pairing.scan.camera")
                    } else {
                        scanPlaceholder(
                            caption: cameraPermission == .denied
                                ? "Camera access is off — paste the code instead."
                                : "Point the camera at the QR your Mac printed."
                        )
                    }
                    #else
                    scanPlaceholder(
                        caption: "Paste the code instead — this device has no usable camera."
                    )
                    #endif

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or paste the code from Terminal")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("naru://pair?code=…", text: $pastedCode)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .font(.footnote.monospaced())
                                .accessibilityIdentifier("naru.pairing.scan.pasteField")
                            Button {
                                deliver(pastedCode)
                            } label: {
                                Text("Pair")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("naru.pairing.scan.pasteSubmit")
                        }
                    }

                    if let failureMessage {
                        Text(failureMessage)
                            .font(.footnote)
                            .foregroundStyle(NaruColors.coral)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("naru.pairing.scan.failure")
                    }

                    Text("Open Naru Helper on your Mac and choose “Pair with iPhone…” (or run NaruHelper --pair in Terminal) to show a fresh code. Every code creates a new pairing token; older codes stop working.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Need the Mac side? Get Naru Helper from the project's GitHub Releases page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Download Naru Helper", destination: URL(string: "https://github.com/midagedev/naru-remote/releases/latest")!)
                        .font(.footnote)
                        .accessibilityIdentifier("naru.pairing.scan.helperDownload")
                }
                .padding(16)
            }
            .background(NaruColors.canvas)
            .navigationTitle("QR 찍어 추가하기")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("naru.pairing.scan.cancel")
                }
            }
        }
        .onAppear {
            refreshCameraPermission()
        }
    }

    private func scanPlaceholder(caption: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(NaruColors.mutedInk)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(NaruColors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("naru.pairing.scan.placeholder")
    }

    private func refreshCameraPermission() {
        #if os(iOS) && canImport(UIKit)
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        guard cameraPermission == .notDetermined else {
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor in
                cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
        #endif
    }

    /// Single decode choke point for both doors; a delivered offer
    /// dismisses this view so a slow second callback cannot re-present.
    private func deliver(_ input: String) {
        guard !didDeliver else {
            return
        }
        do {
            let offer = try NaruPairingOfferWire.decode(input)
            didDeliver = true
            onDecoded(offer)
            dismiss()
        } catch let error as NaruPairingOfferError {
            failureMessage = Self.failureMessage(for: error)
        } catch {
            failureMessage = "This isn't a Naru pairing code."
        }
    }

    /// Fixed catalog (constitution §IV): classify, never echo payload.
    private static func failureMessage(for error: NaruPairingOfferError) -> String {
        switch error {
        case .inputTooLong:
            "That code is too long to be a Naru pairing code."
        case .malformedURL, .malformedCode:
            "This isn't a Naru pairing code. Scan the QR printed by `NaruHelper --pair` on your Mac."
        case .malformedPayload, .invalidField:
            "This pairing code didn't pass validation. Re-run `--pair` on the Mac and scan the new code."
        case .unsupportedVersion:
            "This pairing code came from a different version. Update Naru on the Mac and the phone."
        case .noReachableAddress:
            "This pairing code carries no address to connect to."
        }
    }
}

/// AVCapture wrapper — QR only, one delivery, stopped after the first
/// hit so the delegate never stacks duplicate presentations. iOS only:
/// the macOS host build (`swift test`) compiles the paste fallback path.
#if os(iOS) && canImport(UIKit)
public struct NaruPairingCodeScanner: UIViewControllerRepresentable {
    private let onCode: @MainActor (String) -> Void

    public init(onCode: @escaping @MainActor (String) -> Void) {
        self.onCode = onCode
    }

    public func makeUIViewController(context: Context) -> ScannerViewController {
        ScannerViewController(onCode: onCode)
    }

    public func updateUIViewController(_ controller: ScannerViewController, context: Context) {}

    public final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        private let onCode: @MainActor (String) -> Void
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didDeliver = false

        init(onCode: @escaping @MainActor (String) -> Void) {
            self.onCode = onCode
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        public override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                // No camera (simulator, iPad studio display) — the paste
                // field beside this view is the working door.
                return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
            previewLayer = preview

            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }

        public override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        public override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }

        nonisolated public func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            // Delegate callbacks arrive nonisolated even on a main queue;
            // isolate state access to the main actor explicitly.
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue
            else {
                return
            }
            Task { @MainActor in
                guard !didDeliver else {
                    return
                }
                didDeliver = true
                session.stopRunning()
                onCode(value)
            }
        }
    }
}
#endif

// MARK: - Confirm

/// What the sheet is about to save, presented for an explicit Save tap
/// before anything persists (US-1: no silent writes from a scan).
public struct NaruPairingPendingOffer: Identifiable, Equatable {
    public let id = UUID()
    public let offer: NaruPairingOffer
    public let replacesProfileID: ConnectionProfile.ID?

    public init(offer: NaruPairingOffer, replacesProfileID: ConnectionProfile.ID?) {
        self.offer = offer
        self.replacesProfileID = replacesProfileID
    }
}

public struct NaruPairingConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    private let pending: NaruPairingPendingOffer
    private let onSave: @MainActor (ConnectionProfile, ProfileEditorCredentialUpdate) async -> Void

    @State private var isSaving = false

    public init(
        pending: NaruPairingPendingOffer,
        onSave: @escaping @MainActor (ConnectionProfile, ProfileEditorCredentialUpdate) async -> Void
    ) {
        self.pending = pending
        self.onSave = onSave
    }

    private var primaryAddress: String {
        NaruPairingProfileFactory.hostString(for: pending.offer)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Computer", value: pending.offer.host.label)
                    LabeledContent("Address", value: primaryAddress)
                    LabeledContent("Screen sharing", value: "port \(pending.offer.host.vncPort)")
                    LabeledContent("Helper", value: "text \(pending.offer.helper.textPort) · video \(pending.offer.helper.videoPort)")
                } header: {
                    Text(pending.replacesProfileID == nil ? "Add this computer?" : "Update the saved profile?")
                } footer: {
                    Text(pending.replacesProfileID == nil
                        ? "Naru will save this profile with the pairing from the code."
                        : "A profile for this computer already exists — saving replaces its pairing.")
                }

                Section {
                    Label(
                        pending.offer.vncPassword == nil
                            ? "Screen-sharing password — asked on first connect"
                            : "Screen-sharing password — saved to your Keychain",
                        systemImage: pending.offer.vncPassword == nil ? "questionmark.key.filled" : "key.fill"
                    )
                    Label("Helper pairing token — saved to your Keychain", systemImage: "key.horizontal.fill")
                } header: {
                    Text("What gets saved")
                } footer: {
                    Text("Basic viewing keeps working without the helper (constitution-level guarantee).")
                }
            }
            .navigationTitle("Pair Mac")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("naru.pairing.confirm.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("naru.pairing.confirm.save")
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() async {
        // A decoded offer already passed strict field validation, so a
        // throw here is unreachable in practice; treat it as a no-save
        // rather than crashing the sheet.
        guard let profile = try? NaruPairingProfileFactory.makeProfile(
            offer: pending.offer,
            existingID: pending.replacesProfileID
        ) else {
            return
        }
        isSaving = true
        await onSave(profile, NaruPairingProfileFactory.makeCredentialUpdate(for: pending.offer))
        isSaving = false
        dismiss()
    }
}

// MARK: - Profile factory

/// Pure translation from a decoded offer to the persistence types the
/// profile editor already uses — same credential-reference scheme, same
/// fingerprint source, so a QR-paired profile is indistinguishable from
/// an editor-created one downstream.
public enum NaruPairingProfileFactory {
    public static func hostString(for offer: NaruPairingOffer) -> String {
        offer.host.magicDns ?? offer.host.addresses[0]
    }

    /// Host match first, label match second: a re-run `--pair` may rotate
    /// nothing visible while renaming nothing — either way the existing
    /// profile is updated in place rather than duplicated (US-1 SC-3).
    public static func existingProfileID(
        for offer: NaruPairingOffer,
        in profiles: [ConnectionProfile]
    ) -> ConnectionProfile.ID? {
        let host = hostString(for: offer)
        return profiles.first { $0.host == host || $0.displayName == offer.host.label }?.id
    }

    public static func makeProfile(
        offer: NaruPairingOffer,
        existingID: ConnectionProfile.ID?
    ) throws -> ConnectionProfile {
        let id = existingID ?? UUID()
        let host = hostString(for: offer)
        return try ConnectionProfile(
            id: id,
            displayName: offer.host.label,
            host: host,
            port: Int(offer.host.vncPort),
            username: nil,
            credentialRef: offer.vncPassword == nil ? nil : "vnc-password:\(id.uuidString)",
            favorite: false,
            lastConnectedAt: nil,
            lastDiagnosticSummary: nil,
            hostKind: offer.host.magicDns == nil ? .privateAddress : .magicDNS,
            allowsPiPWatch: true,
            helperTextBridge: try HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: nil,
                port: Int(offer.helper.textPort),
                pairingSecretRef: "helper-token:\(id.uuidString)",
                pairingFingerprint: offer.helper.fingerprint
            ),
            helperVideo: try HelperVideoConnectionConfiguration(
                isEnabled: true,
                isRevoked: false,
                pairingSecretRef: "helper-video-token:\(id.uuidString)",
                pairingFingerprint: offer.helper.fingerprint
            )
        )
    }

    public static func makeCredentialUpdate(
        for offer: NaruPairingOffer
    ) -> ProfileEditorCredentialUpdate {
        ProfileEditorCredentialUpdate(
            vncPassword: offer.vncPassword,
            helperPairingSecret: offer.helper.token,
            helperVideoPairingSecret: offer.helper.token
        )
    }
}
