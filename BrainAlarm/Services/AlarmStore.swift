import Foundation

/// Local persistence of alarm settings. Separate from scheduling on purpose: scheduling can succeed
/// while saving fails, and the save workflow needs to tell those apart.
@MainActor
protocol AlarmStoring: AnyObject {
    func loadAll() throws -> [AlarmSetting]
    func saveAll(_ settings: [AlarmSetting]) throws

    /// Inserts or replaces the setting with the same `id`.
    func save(_ setting: AlarmSetting) throws
    func remove(id: UUID) throws
}

/// Stores settings as JSON in the App Group `UserDefaults`, so intents and the widget can read them.
@MainActor
final class AlarmStore: AlarmStoring {
    private static let settingsKey = "alarmStore.settings"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = AppGroup.sharedDefaults()) {
        self.defaults = defaults
    }

    func loadAll() throws -> [AlarmSetting] {
        guard let data = defaults.data(forKey: AlarmStore.settingsKey) else {
            return []
        }
        do {
            return try decoder.decode([AlarmSetting].self, from: data)
        } catch {
            throw AlarmError.storageFailed(underlying: error)
        }
    }

    func saveAll(_ settings: [AlarmSetting]) throws {
        do {
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: AlarmStore.settingsKey)
        } catch {
            throw AlarmError.storageFailed(underlying: error)
        }
    }

    func save(_ setting: AlarmSetting) throws {
        var settings = try loadAll()
        if let existingIndex = settings.firstIndex(where: { existing in existing.id == setting.id }) {
            settings[existingIndex] = setting
        } else {
            settings.append(setting)
        }
        try saveAll(settings)
    }

    func remove(id: UUID) throws {
        var settings = try loadAll()
        settings.removeAll(where: { existing in existing.id == id })
        try saveAll(settings)
    }
}

extension AlarmStoring {
    /// The alarm the user edits on the main screen: the first one that is not a test alarm.
    func loadUserAlarm() throws -> AlarmSetting? {
        let settings = try loadAll()
        return settings.first(where: { setting in !setting.isTestAlarm })
    }

    /// The setting that owns a given AlarmKit identifier (main or backup), if any.
    func loadSetting(owningAlarmID alarmID: UUID) throws -> AlarmSetting? {
        let settings = try loadAll()
        return settings.first(where: { setting in setting.allScheduledAlarmIDs.contains(alarmID) })
    }
}
