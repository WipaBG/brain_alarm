import XCTest
@testable import BrainAlarm

@MainActor
final class AlarmEditorModelTests: XCTestCase {
    private var service: MockAlarmService!
    private var store: MockAlarmStore!
    private var model: AlarmEditorModel!

    override func setUp() async throws {
        service = MockAlarmService()
        store = MockAlarmStore()
        model = AlarmEditorModel(
            alarmService: service,
            alarmStore: store,
            sessionState: SessionState(defaults: UserDefaults(suiteName: "AlarmEditorModelTests") ?? .standard)
        )
        model.setting.isEnabled = true
    }

    func testSuccessfulSaveStoresMainAndBackupIDs() async throws {
        service.backupCountToReturn = 5

        try await model.saveAlarm(model.setting)

        XCTAssertEqual(store.settings.count, 1)
        let saved = try XCTUnwrap(store.settings.first)
        XCTAssertNotNil(saved.mainAlarmID)
        XCTAssertEqual(saved.backupAlarmIDs.count, 5)
        XCTAssertTrue(saved.isEnabled)
        XCTAssertEqual(service.scheduleMainCallCount, 1)
        XCTAssertEqual(service.scheduleBackupCallCount, 1)
    }

    func testPermissionDeniedStopsBeforeScheduling() async {
        service.permissionState = .denied

        do {
            try await model.saveAlarm(model.setting)
            XCTFail("Expected permissionDenied")
        } catch AlarmError.permissionDenied {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(service.scheduleMainCallCount, 0)
        XCTAssertTrue(store.settings.isEmpty)
    }

    func testSchedulingFailureLeavesNothingSaved() async {
        service.shouldFailScheduling = true

        do {
            try await model.saveAlarm(model.setting)
            XCTFail("Expected schedulingFailed")
        } catch AlarmError.schedulingFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(store.settings.isEmpty)
        XCTAssertEqual(service.scheduleBackupCallCount, 0)
    }

    func testBackupChainFailureCancelsMainAlarm() async {
        service.shouldFailBackupChain = true

        do {
            try await model.saveAlarm(model.setting)
            XCTFail("Expected schedulingFailed")
        } catch AlarmError.schedulingFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(service.cancelledIDs.count, 1, "The already-scheduled main alarm must be cancelled")
        XCTAssertTrue(service.scheduledIDs.isEmpty)
    }

    func testStorageFailureCancelsEverythingJustScheduled() async {
        store.shouldFailSave = true
        service.backupCountToReturn = 3

        do {
            try await model.saveAlarm(model.setting)
            XCTFail("Expected storageFailed")
        } catch AlarmError.storageFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(service.cancelledIDs.count, 4, "main + 3 backups must be cancelled")
        XCTAssertTrue(service.scheduledIDs.isEmpty, "no ghost alarms may remain")
    }

    func testRepeatedSaveTapsScheduleOnlyOnce() async {
        service.scheduleDelayNanoseconds = 50_000_000

        async let firstTap: Void = model.saveButtonTapped()
        async let secondTap: Void = model.saveButtonTapped()
        _ = await (firstTap, secondTap)

        XCTAssertEqual(service.scheduleMainCallCount, 1)
        XCTAssertEqual(model.statusMessage, "Alarm scheduled.")
    }

    func testResavingCancelsPreviousAlarmsFirst() async throws {
        service.backupCountToReturn = 2
        try await model.saveAlarm(model.setting)
        let firstRoundIDs = service.scheduledIDs

        try await model.saveAlarm(model.setting)

        for oldID in firstRoundIDs {
            XCTAssertTrue(service.cancelledIDs.contains(oldID), "old alarm \(oldID) should have been cancelled")
        }
        XCTAssertEqual(store.settings.count, 1, "re-saving must not create a second setting")
    }

    func testInvalidBackupIntervalIsRejectedBeforePermission() async {
        model.setting.backupIntervalSeconds = 5
        service.permissionState = .denied

        do {
            try await model.saveAlarm(model.setting)
            XCTFail("Expected invalidInput")
        } catch AlarmError.invalidInput {
            // expected: validation runs before the permission check
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
