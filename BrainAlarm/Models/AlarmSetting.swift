import Foundation

/// One alarm as the user configured it, plus the AlarmKit identifiers we received when scheduling it.
///
/// The AlarmKit IDs are the link between "what the user wants" and "what the system has scheduled".
/// They are optional because a setting can exist before it is scheduled, or after it was cancelled.
struct AlarmSetting: Codable, Identifiable, Equatable {
    var id: UUID
    var isEnabled: Bool

    /// Time of day, 24-hour clock, in the user's local time zone.
    var hour: Int
    var minute: Int

    /// Days the alarm repeats on. Empty means the alarm fires once and is then disabled.
    var repeatDays: Set<Locale.Weekday>

    var difficulty: PuzzleDifficulty

    /// How many extra alarms follow the main one, and how far apart. See the backup chain in README.
    var backupAlarmCount: Int = 5
    var backupIntervalSeconds: Int = 60

    /// Name of a bundled .wav or .caf file (without directory). nil plays the system default.
    var soundFileName: String?

    /// When set, the main alarm fires once at this exact instant instead of at `hour:minute`.
    /// Used by "Test alarm in 60s" so that development does not have to wait for a wall-clock minute.
    var fixedFireDate: Date?

    /// AlarmKit identifier of the main alarm, once scheduled.
    var mainAlarmID: UUID?

    /// AlarmKit identifiers of the backup alarms, once scheduled, in firing order.
    var backupAlarmIDs: [UUID] = []

    /// True for the temporary alarm created by "Test alarm in 60s".
    var isTestAlarm: Bool { fixedFireDate != nil }

    /// True when the alarm repeats on at least one weekday.
    var isRepeating: Bool { !repeatDays.isEmpty && fixedFireDate == nil }

    /// All AlarmKit identifiers this setting currently owns.
    var allScheduledAlarmIDs: [UUID] {
        var identifiers: [UUID] = []
        if let mainAlarmID {
            identifiers.append(mainAlarmID)
        }
        identifiers.append(contentsOf: backupAlarmIDs)
        return identifiers
    }

    /// A sensible starting point for a brand-new alarm: 07:00, every day, medium difficulty.
    static func makeDefault() -> AlarmSetting {
        AlarmSetting(
            id: UUID(),
            isEnabled: false,
            hour: 7,
            minute: 0,
            repeatDays: Set(Locale.Weekday.allWeekdays),
            difficulty: .medium
        )
    }

    /// A one-shot alarm that fires `seconds` from now, for development iteration.
    static func makeTestAlarm(secondsFromNow seconds: TimeInterval, difficulty: PuzzleDifficulty) -> AlarmSetting {
        let fireDate = Date.now.addingTimeInterval(seconds)
        let components = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
        return AlarmSetting(
            id: UUID(),
            isEnabled: true,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            repeatDays: [],
            difficulty: difficulty,
            backupAlarmCount: 3,
            backupIntervalSeconds: 60,
            fixedFireDate: fireDate
        )
    }
}

extension Locale.Weekday {
    /// Sunday through Saturday, in calendar order. `Locale.Weekday` is not `CaseIterable`.
    static let allWeekdays: [Locale.Weekday] = [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
    ]

    /// The `Calendar` weekday number (1 = Sunday … 7 = Saturday) for this day.
    var calendarWeekdayNumber: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        default: return 1
        }
    }

    /// Short label for weekday toggles, e.g. "Mon".
    var shortLabel: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = calendarWeekdayNumber - 1
        if symbols.indices.contains(index) {
            return symbols[index]
        }
        return rawValue.capitalized
    }
}
