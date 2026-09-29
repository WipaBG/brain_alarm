import Foundation
@testable import BrainAlarm

/// Returns scripted values in order; falls back to the range's lower bound when the script runs out.
struct ScriptedRandomSource: RandomSource {
    private var values: [Int]

    init(_ values: [Int]) {
        self.values = values
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        if values.isEmpty {
            return range.lowerBound
        }
        let next = values.removeFirst()
        return min(max(next, range.lowerBound), range.upperBound)
    }
}

struct TestFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Records every call and can be told to fail at specific steps.
@MainActor
final class MockAlarmService: AlarmScheduling {
    var permissionState: AlarmPermissionState = .authorized
    var shouldFailScheduling = false
    var shouldFailBackupChain = false
    var backupCountToReturn = 2

    /// Simulated delay for `scheduleMainAlarm`, so tests can overlap two saves.
    var scheduleDelayNanoseconds: UInt64 = 0

    private(set) var scheduleMainCallCount = 0
    private(set) var scheduleBackupCallCount = 0
    private(set) var stoppedIDs: [UUID] = []
    private(set) var cancelledIDs: [UUID] = []
    private(set) var scheduledIDs: Set<UUID> = []

    func currentPermissionState() -> AlarmPermissionState {
        permissionState
    }

    func requestAlarmPermissionIfNeeded() async throws {
        if permissionState == .denied {
            throw AlarmError.permissionDenied
        }
        permissionState = .authorized
    }

    func scheduleMainAlarm(for setting: AlarmSetting) async throws -> UUID {
        scheduleMainCallCount += 1
        if scheduleDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: scheduleDelayNanoseconds)
        }
        if shouldFailScheduling {
            throw AlarmError.schedulingFailed(underlying: TestFailure(message: "scheduling failed"))
        }
        let id = UUID()
        scheduledIDs.insert(id)
        return id
    }

    func scheduleBackupChain(for setting: AlarmSetting, mainFireDate: Date) async throws -> [UUID] {
        scheduleBackupCallCount += 1
        if shouldFailBackupChain {
            throw AlarmError.schedulingFailed(underlying: TestFailure(message: "backup failed"))
        }
        let ids = (0..<backupCountToReturn).map { _ in UUID() }
        for id in ids {
            scheduledIDs.insert(id)
        }
        return ids
    }

    func stopAlarm(id: UUID) throws {
        stoppedIDs.append(id)
        scheduledIDs.remove(id)
    }

    func cancelAlarms(ids: [UUID]) throws {
        cancelledIDs.append(contentsOf: ids)
        for id in ids {
            scheduledIDs.remove(id)
        }
    }

    func scheduledAlarmIDs() throws -> Set<UUID> {
        scheduledIDs
    }
}

/// In-memory store that can be told to fail on save.
@MainActor
final class MockAlarmStore: AlarmStoring {
    var shouldFailSave = false
    private(set) var settings: [AlarmSetting] = []

    func loadAll() throws -> [AlarmSetting] {
        settings
    }

    func saveAll(_ settings: [AlarmSetting]) throws {
        if shouldFailSave {
            throw TestFailure(message: "disk full")
        }
        self.settings = settings
    }

    func save(_ setting: AlarmSetting) throws {
        if shouldFailSave {
            throw TestFailure(message: "disk full")
        }
        if let index = settings.firstIndex(where: { existing in existing.id == setting.id }) {
            settings[index] = setting
        } else {
            settings.append(setting)
        }
    }

    func remove(id: UUID) throws {
        settings.removeAll(where: { existing in existing.id == id })
    }
}
