import AlarmKit
import Foundation
import os

/// Permission status in our own words, so views and models never import AlarmKit.
enum AlarmPermissionState: Equatable {
    case notDetermined
    case authorized
    case denied
}

/// Everything the rest of the app needs from the alarm system. `AlarmService` is the real
/// implementation; tests use a mock. Keeping this list short is deliberate.
@MainActor
protocol AlarmScheduling: AnyObject {
    func currentPermissionState() -> AlarmPermissionState

    /// Asks the user for permission if they have never been asked. Throws `AlarmError.permissionDenied`
    /// if they declined (now or earlier).
    func requestAlarmPermissionIfNeeded() async throws

    /// Schedules the alarm the user configured and returns its AlarmKit identifier.
    func scheduleMainAlarm(for setting: AlarmSetting) async throws -> UUID

    /// Schedules the backup alarms that follow `mainFireDate`. Returns their identifiers in firing order.
    func scheduleBackupChain(for setting: AlarmSetting, mainFireDate: Date) async throws -> [UUID]

    /// Silences an alarm that is ringing right now. A repeating alarm stays scheduled for next time.
    func stopAlarm(id: UUID) throws

    /// Removes alarms from the system entirely, whether or not they are ringing.
    func cancelAlarms(ids: [UUID]) throws

    /// Identifiers of every alarm the system still knows about for this app.
    func scheduledAlarmIDs() throws -> Set<UUID>
}

/// The only type in the app that talks to AlarmKit.
///
/// Read this file top to bottom to learn: how permission is requested, how alarms are scheduled,
/// how they are stopped or cancelled, and how the app notices that one started ringing.
@MainActor
final class AlarmService: AlarmScheduling {
    private let alarmManager: AlarmManager
    private let configurationFactory: AlarmConfigurationFactory
    private let sessionState: SessionState
    private let logger = Logger(subsystem: "BrainAlarm", category: "AlarmService")

    /// The one task that listens for alarm changes. Owned here; cancelled in `deinit`.
    private var alarmUpdatesTask: Task<Void, Never>?

    init(
        alarmManager: AlarmManager = .shared,
        configurationFactory: AlarmConfigurationFactory = AlarmConfigurationFactory(),
        sessionState: SessionState = SessionState()
    ) {
        self.alarmManager = alarmManager
        self.configurationFactory = configurationFactory
        self.sessionState = sessionState
    }

    deinit {
        alarmUpdatesTask?.cancel()
    }

    // MARK: Permission

    func currentPermissionState() -> AlarmPermissionState {
        switch alarmManager.authorizationState {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestAlarmPermissionIfNeeded() async throws {
        let currentState = currentPermissionState()

        switch currentState {
        case .authorized:
            return
        case .denied:
            throw AlarmError.permissionDenied
        case .notDetermined:
            break
        }

        let resultingState: AlarmManager.AuthorizationState
        do {
            resultingState = try await alarmManager.requestAuthorization()
        } catch {
            throw AlarmError.schedulingFailed(underlying: error)
        }

        if resultingState != .authorized {
            throw AlarmError.permissionDenied
        }
    }

    // MARK: Scheduling

    func scheduleMainAlarm(for setting: AlarmSetting) async throws -> UUID {
        let alarmID = UUID()
        let configuration = configurationFactory.makeMainAlarmConfiguration(from: setting, alarmID: alarmID)

        do {
            _ = try await alarmManager.schedule(id: alarmID, configuration: configuration)
        } catch {
            throw AlarmError.schedulingFailed(underlying: error)
        }

        logger.info("Scheduled main alarm \(alarmID.uuidString, privacy: .public)")
        return alarmID
    }

    func scheduleBackupChain(for setting: AlarmSetting, mainFireDate: Date) async throws -> [UUID] {
        let fireDates = configurationFactory.backupFireDates(for: setting, mainFireDate: mainFireDate)
        var scheduledIDs: [UUID] = []

        for (offset, fireDate) in fireDates.enumerated() {
            let backupIndex = offset + 1
            let alarmID = UUID()
            let configuration = configurationFactory.makeBackupAlarmConfiguration(
                from: setting,
                alarmID: alarmID,
                backupIndex: backupIndex,
                fireDate: fireDate
            )

            do {
                _ = try await alarmManager.schedule(id: alarmID, configuration: configuration)
            } catch {
                // Don't leave a partial chain behind if one backup fails.
                try cancelAlarms(ids: scheduledIDs)
                throw AlarmError.schedulingFailed(underlying: error)
            }

            scheduledIDs.append(alarmID)
        }

        logger.info("Scheduled \(scheduledIDs.count) backup alarms")
        return scheduledIDs
    }

    // MARK: Stopping and cancelling

    func stopAlarm(id: UUID) throws {
        try alarmManager.stop(id: id)
        logger.info("Stopped alarm \(id.uuidString, privacy: .public)")
    }

    func cancelAlarms(ids: [UUID]) throws {
        for alarmID in ids {
            try alarmManager.cancel(id: alarmID)
        }
        logger.info("Cancelled \(ids.count) alarms")
    }

    func scheduledAlarmIDs() throws -> Set<UUID> {
        let systemAlarms = try alarmManager.alarms
        let identifiers = systemAlarms.map { alarm in alarm.id }
        return Set(identifiers)
    }

    // MARK: Keeping local state honest

    /// Drops any stored alarm ID that the system no longer has. A one-shot alarm disappears from the
    /// system once it has fired and stopped, so our saved setting must not keep claiming it exists.
    func reconcileWithSystem(store: any AlarmStoring) throws {
        let systemIDs = try scheduledAlarmIDs()
        var settings = try store.loadAll()

        for index in settings.indices {
            var setting = settings[index]

            if let mainAlarmID = setting.mainAlarmID, !systemIDs.contains(mainAlarmID) {
                setting.mainAlarmID = nil
            }
            setting.backupAlarmIDs = setting.backupAlarmIDs.filter { backupID in
                systemIDs.contains(backupID)
            }
            if setting.allScheduledAlarmIDs.isEmpty {
                setting.isEnabled = false
            }

            settings[index] = setting
        }

        try store.saveAll(settings)
    }

    /// Starts watching the system for an alarm that begins alerting while the app is running,
    /// so the puzzle can appear even if the user never touches the Lock Screen buttons.
    func startObservingAlarmUpdates() {
        if alarmUpdatesTask != nil {
            return
        }

        alarmUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await alarms in self.alarmManager.alarmUpdates {
                self.handleAlarmUpdate(alarms)
            }
        }
    }

    private func handleAlarmUpdate(_ alarms: [Alarm]) {
        let alertingAlarm = alarms.first(where: { alarm in alarm.state == .alerting })
        guard let alertingAlarm else {
            return
        }

        // Only flip the flag once per ring; otherwise a solved puzzle could be re-shown.
        if sessionState.ringingAlarmID != alertingAlarm.id {
            sessionState.markAlarmRinging(alarmID: alertingAlarm.id)
        }
    }
}
