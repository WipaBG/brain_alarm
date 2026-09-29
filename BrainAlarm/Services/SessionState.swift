import Foundation

/// The handful of flags that answer "should the puzzle be on screen right now?".
///
/// Stored in App Group `UserDefaults` so that App Intents (which may run before the UI exists)
/// and the app itself agree, and so the answer survives the app being killed while ringing.
///
/// Compiled into both the app and the widget extension.
struct SessionState: Sendable {
    /// Posted in-process whenever a flag changes, so SwiftUI can re-check `needsPuzzle`.
    static let didChangeNotification = Notification.Name("BrainAlarm.SessionState.didChange")

    private enum Key {
        static let isAlarmRinging = "session.isAlarmRinging"
        static let isPuzzleSolved = "session.isPuzzleSolved"
        static let ringingAlarmID = "session.ringingAlarmID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.sharedDefaults()) {
        self.defaults = defaults
    }

    /// True from the moment an alarm alerts (or the user taps Stop/Solve) until the puzzle is solved.
    var isAlarmRinging: Bool {
        defaults.bool(forKey: Key.isAlarmRinging)
    }

    /// True once the user has solved the puzzle for the current ring.
    var isPuzzleSolved: Bool {
        defaults.bool(forKey: Key.isPuzzleSolved)
    }

    /// The AlarmKit identifier of the alarm that is (or was last) ringing.
    var ringingAlarmID: UUID? {
        guard let stored = defaults.string(forKey: Key.ringingAlarmID) else {
            return nil
        }
        return UUID(uuidString: stored)
    }

    /// The single question the router asks on launch and on every foreground.
    var needsPuzzle: Bool {
        isAlarmRinging && !isPuzzleSolved
    }

    /// Call when an alarm starts alerting, or when the user taps Stop or Solve on the alert.
    func markAlarmRinging(alarmID: UUID) {
        defaults.set(true, forKey: Key.isAlarmRinging)
        defaults.set(false, forKey: Key.isPuzzleSolved)
        defaults.set(alarmID.uuidString, forKey: Key.ringingAlarmID)
        notifyChange()
    }

    /// Call once the puzzle streak is complete and the alarm chain has been cancelled.
    func markPuzzleSolved() {
        defaults.set(false, forKey: Key.isAlarmRinging)
        defaults.set(true, forKey: Key.isPuzzleSolved)
        notifyChange()
    }

    /// Clears everything, for example when the user disables the alarm.
    func reset() {
        defaults.removeObject(forKey: Key.isAlarmRinging)
        defaults.removeObject(forKey: Key.isPuzzleSolved)
        defaults.removeObject(forKey: Key.ringingAlarmID)
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: SessionState.didChangeNotification, object: nil)
    }
}
