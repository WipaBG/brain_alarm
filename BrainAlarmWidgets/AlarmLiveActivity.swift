import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// Live Activity for BrainAlarm alarms. AlarmKit requires one to exist; the alerting UI itself is
/// drawn by the system from `AlarmPresentation.Alert`. This is the smallest configuration that
/// compiles and rings. Polish comes last.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<BrainAlarmMetadata>.self) { context in
            lockScreenView(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    solveButton(alarmID: context.state.alarmID)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                Image(systemName: "brain.head.profile")
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(_ context: ActivityViewContext<AlarmAttributes<BrainAlarmMetadata>>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.title2)
                .foregroundStyle(context.attributes.tintColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.presentation.alert.title)
                    .font(.headline)
                if let metadata = context.attributes.metadata, metadata.isBackupAlarm {
                    Text("Backup \(metadata.backupIndex)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            solveButton(alarmID: context.state.alarmID)
        }
        .padding()
    }

    private func solveButton(alarmID: UUID) -> some View {
        Button(intent: OpenPuzzleIntent(alarmID: alarmID)) {
            Label("Solve", systemImage: "brain.head.profile")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
    }
}
