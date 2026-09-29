import SwiftUI

/// Shown instead of the editor when the user has denied AlarmKit permission.
/// The only fix is in Settings, so this screen just points there.
struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "alarm.waves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Alarms are turned off")
                .font(.title2.weight(.bold))

            Text("BrainAlarm needs permission to schedule alarms that ring in Silent mode. Turn it on in Settings, then come back.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settingsURL)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
