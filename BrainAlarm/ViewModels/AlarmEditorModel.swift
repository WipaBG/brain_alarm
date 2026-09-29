import Foundation
import Observation

/// Screen state and the save workflow for the alarm editor.
///
/// The view binds to the properties; every button calls one method here; this class talks to
/// `AlarmScheduling` and `AlarmStoring`. No AlarmKit types appear in this file.
@MainActor
@Observable
final class AlarmEditorModel {
    /// The alarm being edited. Loaded from the store, or a default if none is saved yet.
    var setting: AlarmSetting = .makeDefault()

    /// True while a save or test is in flight. The view disables Save while this is true.
    private(set) var isSchedulingAlarm = false

    var errorMessage: String?
    var statusMessage: String?
    private(set) var permissionState: AlarmPermissionState = .notDetermined
    private(set) var nextFireDate: Date?

    private let alarmService: any AlarmScheduling
    private let alarmStore: any AlarmStoring
    private let configurationFactory: AlarmConfigurationFactory
    private let sessionState: SessionState

    init(
        alarmService: any AlarmScheduling,
        alarmStore: any AlarmStoring,
        configurationFactory: AlarmConfigurationFactory = AlarmConfigurationFactory(),
        sessionState: SessionState = SessionState()
    ) {
        self.alarmService = alarmService
        self.alarmStore = alarmStore
        self.configurationFactory = configurationFactory
        self.sessionState = sessionState
    }

    // MARK: Values the view binds to

    /// The wheel picker works with a `Date`; the setting stores hour and minute.
    var selectedTime: Date {
        get {
            var components = DateComponents()
            components.hour = setting.hour
            components.minute = setting.minute
            return Calendar.current.date(from: components) ?? .now
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            setting.hour = components.hour ?? setting.hour
            setting.minute = components.minute ?? setting.minute
            refreshNextFireDate()
        }
    }

    func isRepeatDaySelected(_ weekday: Locale.Weekday) -> Bool {
        setting.repeatDays.contains(weekday)
    }

    func toggleRepeatDay(_ weekday: Locale.Weekday) {
        if setting.repeatDays.contains(weekday) {
            setting.repeatDays.remove(weekday)
        } else {
            setting.repeatDays.insert(weekday)
        }
        refreshNextFireDate()
    }

    // MARK: Loading

    func load() {
        permissionState = alarmService.currentPermissionState()

        do {
            if let savedSetting = try alarmStore.loadUserAlarm() {
                setting = savedSetting
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refreshNextFireDate()
    }

    // MARK: Button actions

    /// Save button. Schedules the alarm if it is enabled, otherwise cancels whatever was scheduled.
    func saveButtonTapped() async {
        if isSchedulingAlarm {
            return
        }
        isSchedulingAlarm = true
        defer { isSchedulingAlarm = false }

        errorMessage = nil
        statusMessage = nil

        do {
            if setting.isEnabled {
                try await saveAlarm(setting)
                // Only claim success after AlarmKit actually returned.
                statusMessage = "Alarm scheduled."
            } else {
                try await cancelAlarm(setting)
                statusMessage = "Alarm disabled."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        permissionState = alarmService.currentPermissionState()
        refreshNextFireDate()
    }

    /// "Test alarm in 60s". Schedules a separate one-shot alarm so the real alarm is untouched.
    func testAlarmButtonTapped(secondsFromNow seconds: TimeInterval = 60) async {
        if isSchedulingAlarm {
            return
        }
        isSchedulingAlarm = true
        defer { isSchedulingAlarm = false }

        errorMessage = nil
        statusMessage = nil

        let testSetting = AlarmSetting.makeTestAlarm(secondsFromNow: seconds, difficulty: setting.difficulty)

        do {
            try await saveAlarm(testSetting)
            statusMessage = "Test alarm rings in \(Int(seconds)) seconds. Lock the phone."
        } catch {
            errorMessage = error.localizedDescription
        }

        permissionState = alarmService.currentPermissionState()
    }

    // MARK: The save workflow

    /// Schedules the user's alarm plus its backup chain, then remembers it locally.
    /// Read top to bottom: validate → permission → clear old → schedule main → schedule backups → save.
    func saveAlarm(_ setting: AlarmSetting) async throws {
        try validate(setting)                                           // → AlarmError.invalidInput
        try await alarmService.requestAlarmPermissionIfNeeded()         // → AlarmError.permissionDenied
        try cancelPreviouslyScheduledAlarms(for: setting)

        guard let mainFireDate = configurationFactory.nextMainFireDate(for: setting) else {
            throw AlarmError.invalidInput(reason: "No future time matches this alarm.")
        }

        let mainAlarmID = try await alarmService.scheduleMainAlarm(for: setting)      // → .schedulingFailed

        let backupAlarmIDs: [UUID]
        do {
            backupAlarmIDs = try await alarmService.scheduleBackupChain(for: setting, mainFireDate: mainFireDate)
        } catch {
            // The main alarm is already in the system; don't leave it there without its chain.
            try alarmService.cancelAlarms(ids: [mainAlarmID])
            throw error
        }

        var savedSetting = setting
        savedSetting.isEnabled = true
        savedSetting.mainAlarmID = mainAlarmID
        savedSetting.backupAlarmIDs = backupAlarmIDs

        do {
            try alarmStore.save(savedSetting)                            // → .storageFailed
        } catch {
            // Don't leave ghost alarms behind if we can't remember them.
            try alarmService.cancelAlarms(ids: [mainAlarmID] + backupAlarmIDs)
            throw AlarmError.storageFailed(underlying: error)
        }

        if !savedSetting.isTestAlarm {
            self.setting = savedSetting
        }
    }

    /// Removes the alarm and its backups from the system and marks the setting disabled.
    func cancelAlarm(_ setting: AlarmSetting) async throws {
        try cancelPreviouslyScheduledAlarms(for: setting)

        var disabledSetting = setting
        disabledSetting.isEnabled = false
        disabledSetting.mainAlarmID = nil
        disabledSetting.backupAlarmIDs = []
        try alarmStore.save(disabledSetting)

        self.setting = disabledSetting
        sessionState.reset()
    }

    // MARK: Helpers

    private func validate(_ setting: AlarmSetting) throws {
        guard (0...23).contains(setting.hour) else {
            throw AlarmError.invalidInput(reason: "Hour must be between 0 and 23.")
        }
        guard (0...59).contains(setting.minute) else {
            throw AlarmError.invalidInput(reason: "Minute must be between 0 and 59.")
        }
        guard (0...20).contains(setting.backupAlarmCount) else {
            throw AlarmError.invalidInput(reason: "Backup alarm count must be between 0 and 20.")
        }
        guard setting.backupIntervalSeconds >= 30 else {
            throw AlarmError.invalidInput(reason: "Backup interval must be at least 30 seconds.")
        }
        if let fixedFireDate = setting.fixedFireDate, fixedFireDate <= .now {
            throw AlarmError.invalidInput(reason: "The test alarm time is already in the past.")
        }
    }

    /// Cancels the alarms a previous save created for this setting, ignoring IDs the system already dropped.
    private func cancelPreviouslyScheduledAlarms(for setting: AlarmSetting) throws {
        let settings = try alarmStore.loadAll()
        guard let previous = settings.first(where: { stored in stored.id == setting.id }) else {
            return
        }

        let systemIDs = try alarmService.scheduledAlarmIDs()
        let idsStillInSystem = previous.allScheduledAlarmIDs.filter { alarmID in
            systemIDs.contains(alarmID)
        }
        try alarmService.cancelAlarms(ids: idsStillInSystem)
    }

    private func refreshNextFireDate() {
        nextFireDate = configurationFactory.nextMainFireDate(for: setting)
    }
}
