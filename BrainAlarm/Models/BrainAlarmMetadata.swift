import AlarmKit

/// Extra information attached to every scheduled alarm. AlarmKit hands it back to the widget
/// so the Live Activity can tell a backup alarm from the main one.
///
/// Compiled into both the app and the widget extension.
struct BrainAlarmMetadata: AlarmMetadata {
    /// False for the alarm the user set; true for the alarms in the backup chain.
    var isBackupAlarm: Bool

    /// 0 for the main alarm, 1…n for backups in firing order.
    var backupIndex: Int

    static let main = BrainAlarmMetadata(isBackupAlarm: false, backupIndex: 0)

    static func backup(index: Int) -> BrainAlarmMetadata {
        BrainAlarmMetadata(isBackupAlarm: true, backupIndex: index)
    }
}
