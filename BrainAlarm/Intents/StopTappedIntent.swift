import AppIntents
import Foundation
import os

/// Runs when the user taps the system Stop button on the alarm alert.
///
/// We cannot remove that button, so we make it behave like "Solve": the ringing alarm goes quiet,
/// the app opens on the puzzle, and the backup chain stays scheduled. Only a solved puzzle
/// cancels the backups.
struct StopTappedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop alarm"
    static let description = IntentDescription("Silences the current alarm and opens the puzzle.")

    /// Bring the app to the foreground after `perform()` runs, so Stop lands on the puzzle.
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let ringingAlarmID = UUID(uuidString: alarmID) else {
            return .result()
        }

        SessionState().markAlarmRinging(alarmID: ringingAlarmID)

        // Stop only this alarm's sound. Do NOT cancel the backups here.
        do {
            try AlarmService().stopAlarm(id: ringingAlarmID)
        } catch {
            // The system usually stops the alert itself when Stop is tapped, so a "not found" error
            // here is expected and harmless. Log it rather than showing the user an error.
            Logger(subsystem: "BrainAlarm", category: "StopTappedIntent")
                .notice("stopAlarm failed after Stop tap: \(error.localizedDescription, privacy: .public)")
        }

        return .result()
    }
}
