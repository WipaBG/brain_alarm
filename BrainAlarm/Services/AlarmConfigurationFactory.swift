import AlarmKit
import Foundation
import SwiftUI

/// Turns an `AlarmSetting` into the AlarmKit objects needed to schedule it, and answers
/// the date questions ("when does this fire next?") that the backup chain depends on.
///
/// Pure functions with no side effects, so they are easy to unit test.
struct AlarmConfigurationFactory {
    var calendar: Calendar = .current
    var tintColor: Color = .orange

    /// Titles shown on the backup alarms, in order. Repeats from the start if there are more backups.
    static let backupTitles: [String] = [
        "Still asleep? Solve the puzzle.",
        "Nice try. Solve it.",
        "The puzzle is still waiting.",
        "Get up. Solve the puzzle.",
        "Last call. Solve it now.",
    ]

    // MARK: Configurations

    func makeMainAlarmConfiguration(
        from setting: AlarmSetting,
        alarmID: UUID
    ) -> AlarmManager.AlarmConfiguration<BrainAlarmMetadata> {
        let attributes = makeAttributes(title: "Wake up. Solve the puzzle.", metadata: .main)

        return .alarm(
            schedule: makeMainSchedule(from: setting),
            attributes: attributes,
            stopIntent: StopTappedIntent(alarmID: alarmID),
            secondaryIntent: OpenPuzzleIntent(alarmID: alarmID),
            sound: makeSound(from: setting)
        )
    }

    func makeBackupAlarmConfiguration(
        from setting: AlarmSetting,
        alarmID: UUID,
        backupIndex: Int,
        fireDate: Date
    ) -> AlarmManager.AlarmConfiguration<BrainAlarmMetadata> {
        let titleIndex = (backupIndex - 1) % AlarmConfigurationFactory.backupTitles.count
        let title = AlarmConfigurationFactory.backupTitles[titleIndex]
        let attributes = makeAttributes(title: title, metadata: .backup(index: backupIndex))

        // Fixed schedule for backup alarms: they must fire at exact instants after the main alarm.
        return .alarm(
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: StopTappedIntent(alarmID: alarmID),
            secondaryIntent: OpenPuzzleIntent(alarmID: alarmID),
            sound: makeSound(from: setting)
        )
    }

    // MARK: Schedules

    func makeMainSchedule(from setting: AlarmSetting) -> Alarm.Schedule {
        if let fixedFireDate = setting.fixedFireDate {
            // Test alarms fire once at an exact instant.
            return .fixed(fixedFireDate)
        }

        // Relative schedule so 07:00 follows the user's local time zone (e.g. when travelling).
        let time = Alarm.Schedule.Relative.Time(hour: setting.hour, minute: setting.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence
        if setting.repeatDays.isEmpty {
            recurrence = .never
        } else {
            let orderedDays = Locale.Weekday.allWeekdays.filter { weekday in
                setting.repeatDays.contains(weekday)
            }
            recurrence = .weekly(orderedDays)
        }

        return .relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
    }

    // MARK: Dates

    /// The next instant the main alarm will fire, or nil if the setting can never fire.
    func nextMainFireDate(for setting: AlarmSetting, after referenceDate: Date = .now) -> Date? {
        if let fixedFireDate = setting.fixedFireDate {
            return fixedFireDate
        }

        var timeOfDay = DateComponents()
        timeOfDay.hour = setting.hour
        timeOfDay.minute = setting.minute
        timeOfDay.second = 0

        guard var candidate = calendar.nextDate(
            after: referenceDate,
            matching: timeOfDay,
            matchingPolicy: .nextTime
        ) else {
            return nil
        }

        if setting.repeatDays.isEmpty {
            return candidate
        }

        let allowedWeekdayNumbers = Set(setting.repeatDays.map { weekday in weekday.calendarWeekdayNumber })

        // At most seven steps are needed to reach an allowed weekday.
        for _ in 0..<7 {
            let candidateWeekday = calendar.component(.weekday, from: candidate)
            if allowedWeekdayNumbers.contains(candidateWeekday) {
                return candidate
            }
            guard let nextCandidate = calendar.nextDate(
                after: candidate,
                matching: timeOfDay,
                matchingPolicy: .nextTime
            ) else {
                return nil
            }
            candidate = nextCandidate
        }

        return nil
    }

    /// The instants the backup alarms fire: T+interval, T+2·interval, … for `backupAlarmCount` alarms.
    func backupFireDates(for setting: AlarmSetting, mainFireDate: Date) -> [Date] {
        guard setting.backupAlarmCount > 0, setting.backupIntervalSeconds > 0 else {
            return []
        }

        return (1...setting.backupAlarmCount).map { backupIndex in
            let offsetSeconds = TimeInterval(backupIndex * setting.backupIntervalSeconds)
            return mainFireDate.addingTimeInterval(offsetSeconds)
        }
    }

    // MARK: Presentation

    private func makeAttributes(title: String, metadata: BrainAlarmMetadata) -> AlarmAttributes<BrainAlarmMetadata> {
        // The Stop control is provided by the system and cannot be removed. Our "Solve" button is
        // the secondary button; `.custom` makes it run `OpenPuzzleIntent`, which opens the app.
        let solveButton = AlarmButton(
            text: "Solve",
            textColor: .white,
            systemImageName: "brain.head.profile"
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: solveButton,
            secondaryButtonBehavior: .custom
        )
        let presentation = AlarmPresentation(alert: alert)

        return AlarmAttributes(presentation: presentation, metadata: metadata, tintColor: tintColor)
    }

    private func makeSound(from setting: AlarmSetting) -> AlertConfiguration.AlertSound {
        if let soundFileName = setting.soundFileName {
            return .named(soundFileName)
        }
        return .default
    }
}
