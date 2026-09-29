import SwiftUI

/// The main screen: pick a time, days, and difficulty; save; or fire a test alarm.
struct AlarmEditorView: View {
    @Bindable var model: AlarmEditorModel

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                repeatDaysSection
                difficultySection
                statusSection
                actionsSection
            }
            .navigationTitle("BrainAlarm")
        }
        .task {
            model.load()
        }
    }

    // MARK: Sections

    private var timeSection: some View {
        Section {
            DatePicker(
                "Alarm time",
                selection: $model.selectedTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()

            Toggle("Enabled", isOn: $model.setting.isEnabled)
        }
    }

    private var repeatDaysSection: some View {
        Section("Repeat") {
            HStack(spacing: 8) {
                ForEach(Locale.Weekday.allWeekdays, id: \.rawValue) { weekday in
                    weekdayButton(weekday)
                }
            }
            .frame(maxWidth: .infinity)

            if model.setting.repeatDays.isEmpty {
                Text("Rings once, then turns itself off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weekdayButton(_ weekday: Locale.Weekday) -> some View {
        let isSelected = model.isRepeatDaySelected(weekday)

        return Button {
            model.toggleRepeatDay(weekday)
        } label: {
            Text(weekday.shortLabel)
                .font(.caption.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var difficultySection: some View {
        Section("Puzzle") {
            Picker("Difficulty", selection: $model.setting.difficulty) {
                ForEach(PuzzleDifficulty.allCases) { difficulty in
                    Text(difficulty.displayName).tag(difficulty)
                }
            }
            .pickerStyle(.segmented)

            Text("\(model.setting.difficulty.requiredCorrectAnswers) correct in a row to silence the alarm.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Permission", value: permissionLabel)

            if let nextFireDate = model.nextFireDate {
                LabeledContent("Next ring", value: nextFireDate.formatted(date: .abbreviated, time: .shortened))
            }

            LabeledContent("Backups", value: "\(model.setting.backupAlarmCount) × \(model.setting.backupIntervalSeconds)s")

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .foregroundStyle(.green)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task {
                    await model.saveButtonTapped()
                }
            } label: {
                HStack {
                    Text(model.setting.isEnabled ? "Save alarm" : "Disable alarm")
                    if model.isSchedulingAlarm {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.isSchedulingAlarm)

            Button("Test alarm in 60s") {
                Task {
                    await model.testAlarmButtonTapped()
                }
            }
            .disabled(model.isSchedulingAlarm)
        } footer: {
            Text("The test alarm is a separate one-shot alarm with a short backup chain. Lock the phone after tapping.")
        }
    }

    private var permissionLabel: String {
        switch model.permissionState {
        case .notDetermined: return "Not asked yet"
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        }
    }
}
