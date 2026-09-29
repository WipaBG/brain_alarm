import Foundation

/// Identifiers shared between the app, the widget extension, and App Intents.
///
/// Compiled into both the app and the widget extension.
enum AppGroup {
    /// Must match `com.apple.security.application-groups` in both entitlements files (see project.yml).
    static let identifier = "group.com.nyagolov.brainalarm"

    /// `UserDefaults` visible to every process in the App Group.
    /// Falls back to standard defaults only if the entitlement is missing, so the app still runs
    /// (but the widget and app will then not see each other's state).
    static func sharedDefaults() -> UserDefaults {
        if let shared = UserDefaults(suiteName: identifier) {
            return shared
        }
        return UserDefaults.standard
    }
}
