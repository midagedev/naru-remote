import SwiftUI

public struct RemoteInputDockView: View {
    @State private var text: String

    private let initialText: String
    private let statusText: String
    private let onSend: (String) -> Void

    public init(
        initialText: String,
        statusText: String,
        onSend: @escaping (String) -> Void = { _ in }
    ) {
        self.initialText = initialText
        self._text = State(initialValue: initialText)
        self.statusText = statusText
        self.onSend = onSend
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Remote Input Dock", systemImage: "keyboard")
                    .font(.headline)

                Spacer()

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 72, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.74))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black.opacity(0.10), lineWidth: 1)
                    )
                    .accessibilityLabel("Remote input text")
                    .accessibilityIdentifier("naru.input.editor")

                Button {
                    onSend(text)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty)
                .help("Send composed text")
                .accessibilityIdentifier("naru.input.send")
            }
        }
        .padding(16)
        .background(Color(red: 0.91, green: 0.94, blue: 0.94))
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityIdentifier("naru.input.dock")
        .onChange(of: initialText) { _, newValue in
            text = newValue
        }
    }
}
