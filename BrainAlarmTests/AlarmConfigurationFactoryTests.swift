import AlarmKit
import XCTest
@testable import BrainAlarm

final class AlarmConfigurationFactoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Sofia") ?? .current
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? .distantPast
    }

    func testMainScheduleIsRelativeForTimeOfDayAlarms() {
        let factory = AlarmConfigurationFactory(calendar: calendar)
        var setting = AlarmSetting.makeDefault()
        setting.repeatDays = [.monday, .friday]

        let schedule = factory.makeMainSchedule(from: setting)

        guard case .relative(let relative) = schedule else {
            return XCTFail("Expected a relative schedule, got \(schedule)")
        }
        XCTAssertEqual(relative.time.hour, 7)
        XCTAssertEqual(relative.time.minute, 0)
        guard case .weekly(let days) = relative.repeats else {
            return XCTFail("Expected weekly recurrence")
        }
        XCTAssertEqual(days, [.monday, .friday])
    }

    func testMainScheduleIsFixedForTestAlarms() {
        let factory = AlarmConfigurationFactory(calendar: calendar)
        let fireDate = Date.now.addingTimeInterval(60)
        var setting = AlarmSetting.makeTestAlarm(secondsFromNow: 60, difficulty: .easy)
        setting.fixedFireDate = fireDate

        let schedule = factory.makeMainSchedule(from: setting)

        guard case .fixed(let date) = schedule else {
            return XCTFail("Expected a fixed schedule, got \(schedule)")
        }
        XCTAssertEqual(date, fireDate)
    }

    func testNextFireDateSkipsToAllowedWeekday() {
        let factory = AlarmConfigurationFactory(calendar: calendar)
        var setting = AlarmSetting.makeDefault()
        setting.hour = 7
        setting.minute = 30
        setting.repeatDays = [.monday]

        // Wednesday 2026-09-30 at 10:00 → next Monday 2026-10-05 at 07:30.
        let reference = makeDate(year: 2026, month: 9, day: 30, hour: 10, minute: 0)
        let expected = makeDate(year: 2026, month: 10, day: 5, hour: 7, minute: 30)

        XCTAssertEqual(factory.nextMainFireDate(for: setting, after: reference), expected)
    }

    func testNextFireDateIsTodayWhenTimeHasNotPassed() {
        let factory = AlarmConfigurationFactory(calendar: calendar)
        var setting = AlarmSetting.makeDefault()
        setting.hour = 22
        setting.minute = 0
        setting.repeatDays = []

        let reference = makeDate(year: 2026, month: 9, day: 30, hour: 10, minute: 0)
        let expected = makeDate(year: 2026, month: 9, day: 30, hour: 22, minute: 0)

        XCTAssertEqual(factory.nextMainFireDate(for: setting, after: reference), expected)
    }

    func testBackupFireDatesAreEvenlySpacedAfterMain() {
        let factory = AlarmConfigurationFactory(calendar: calendar)
        var setting = AlarmSetting.makeDefault()
        setting.backupAlarmCount = 3
        setting.backupIntervalSeconds = 60
        let mainFireDate = makeDate(year: 2026, month: 9, day: 30, hour: 7, minute: 0)

        let dates = factory.backupFireDates(for: setting, mainFireDate: mainFireDate)

        XCTAssertEqual(dates, [
            mainFireDate.addingTimeInterval(60),
            mainFireDate.addingTimeInterval(120),
            mainFireDate.addingTimeInterval(180),
        ])
    }

    func testZeroBackupsProducesNoDates() {
        let factory = AlarmConfigurationFactory(calendar: calendar)
        var setting = AlarmSetting.makeDefault()
        setting.backupAlarmCount = 0

        XCTAssertTrue(factory.backupFireDates(for: setting, mainFireDate: .now).isEmpty)
    }
}
