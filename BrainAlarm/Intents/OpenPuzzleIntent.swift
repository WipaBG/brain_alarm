import AppIntents
import Foundation

/// Runs when the user taps "Solve" on the alarm alert or in the Live Activity.
/// It records that an alarm is ringing and opens the app, which routes straight to the puzzle.
///
/// Compiled into both the app and the widget extension. Deliberately does not import AlarmKit.
struct OpenPuzzleIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Solve the puzzle"
    static let description = IntentDescription("Opens BrainAlarm so you can solve the puzzle and silence the alarm.")

    /// Bring the app to the foreground after `perform()` runs.
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let ringingAlarmID = UUID(uuidString: alarmID) {
            SessionState().markAlarmRinging(alarmID: ringingAlarmID)
        }
        return .result()
    }
}
