import Foundation

/// In-memory form-state model for the profile editor SwiftUI view.
///
/// Centralizes the validation rules (display name + host non-empty,
/// port in `1...65535`) so the SwiftUI view consumes a single source
/// of truth for `Save` enablement and inline error captions, and so
/// the rules can be unit-tested without spinning up the SwiftUI layer.
///
/// The struct is value-typed and `Sendable` — the view holds it as
/// `@State` and rebuilds it on every keystroke; tests construct one
/// directly and assert against the computed properties.
public struct ProfileEditorFormState: Equatable, Sendable {
    public var displayName: String
    public var host: String
    /// Port stored as the raw `String` from the SwiftUI `TextField`
    /// so partial / invalid input ("", "abc", "0") can be rendered
    /// back to the user verbatim with an inline error caption rather
    /// than being silently coerced.
    public var port: String

    public init(
        displayName: String = "",
        host: String = "",
        port: String = "5900"
    ) {
        self.displayName = displayName
        self.host = host
        self.port = port
    }

    // MARK: - Field-level validation

    /// `nil` when the trimmed display name is non-empty.  Returns a
    /// safe-catalog error string otherwise.
    public var displayNameError: String? {
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Profile name is required."
        }
        return nil
    }

    /// `nil` when the trimmed host is non-empty.
    public var hostError: String? {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Host is required."
        }
        return nil
    }

    /// `nil` when the port string parses as an integer in
    /// `1...65535`.  An empty string maps to "Port is required."
    /// rather than "Port must be a number." so the user sees a
    /// concrete next step on the empty-form first paint.
    public var portError: String? {
        let trimmed = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Port is required."
        }
        guard let value = Int(trimmed) else {
            return "Port must be a number."
        }
        if !(1...65535).contains(value) {
            return "Port must be between 1 and 65535."
        }
        return nil
    }

    // MARK: - Aggregate gate

    /// `true` when every field is valid.  The Save button binds to
    /// this through `.disabled(!isValid)` so an empty / malformed
    /// form cannot be persisted.  Mirrors the rules in
    /// `ConnectionProfile.init(...)` so the error never bubbles up
    /// from the throwing initializer at save time.
    public var isValid: Bool {
        displayNameError == nil && hostError == nil && portError == nil
    }

    /// Parsed port value when the form is valid, or `nil` otherwise.
    /// Provided as a convenience for the save path so it does not
    /// have to re-parse the string.
    public var parsedPort: Int? {
        guard let value = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(value)
        else {
            return nil
        }
        return value
    }
}
