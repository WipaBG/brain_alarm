# BrainAlarm

A personal iOS alarm that cannot be silenced for good until you solve a short math puzzle.
Built on AlarmKit (iOS 26+), so it rings through Silent mode and Focus like the system Clock.

## Building

Requirements: a Mac with Xcode 26, an iPhone running iOS 26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
AlarmKit alarms do not reliably ring in the Simulator, so test on the device.

```sh
brew install xcodegen
xcodegen generate            # creates BrainAlarm.xcodeproj from project.yml
open BrainAlarm.xcodeproj
```

Before the first build:

1. Bundle IDs use the `com.nyagolov` prefix. Set `DEVELOPMENT_TEAM` in `project.yml`, or pick your team in Xcode's Signing tab for both targets.
2. `AppGroup.identifier` in `BrainAlarm/Models/AppGroup.swift` must stay in sync with the `com.apple.security.application-groups` entries in `project.yml`.
3. Run the `BrainAlarm` scheme on your iPhone.

Unit tests (Simulator is fine for these; they do not touch AlarmKit):

```sh
xcodebuild test -scheme BrainAlarm -destination 'platform=iOS Simulator,name=iPhone 17'
# one test class:
xcodebuild test -scheme BrainAlarm -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BrainAlarmTests/PuzzleGeneratorTests
```

## File map

| Path | What it does |
|---|---|
| `BrainAlarm/App/BrainAlarmApp.swift` | Entry point. Root view picks editor vs. permission screen and lays the puzzle over both. |
| `BrainAlarm/App/AppRouter.swift` | Owns the services and screen models. Requests permission, reconciles, observes, and decides when the puzzle shows. |
| `BrainAlarm/Models/AlarmSetting.swift` | One alarm as configured: time, days, difficulty, backup chain settings, and the AlarmKit IDs. |
| `BrainAlarm/Models/PuzzleDifficulty.swift` | Easy / medium / hard and how many correct answers each requires. |
| `BrainAlarm/Models/AlarmError.swift` | The four distinct failure cases. |
| `BrainAlarm/Models/BrainAlarmMetadata.swift` | Data attached to each alarm (is it a backup, which index). Shared with the widget. |
| `BrainAlarm/Models/AppGroup.swift` | App Group identifier and shared `UserDefaults`. Shared with the widget. |
| `BrainAlarm/Services/AlarmService.swift` | **The only file that calls AlarmKit.** Permission, schedule, stop, cancel, observe, reconcile. |
| `BrainAlarm/Services/AlarmConfigurationFactory.swift` | Builds AlarmKit configurations from an `AlarmSetting`; computes next fire date and backup dates. |
| `BrainAlarm/Services/AlarmStore.swift` | Saves and loads settings as JSON in App Group `UserDefaults`. |
| `BrainAlarm/Services/SessionState.swift` | The "is an alarm ringing / was the puzzle solved" flags. Shared with the widget. |
| `BrainAlarm/Services/PuzzleGenerator.swift` | Makes arithmetic problems and checks answers. Takes an injectable random source. |
| `BrainAlarm/Intents/OpenPuzzleIntent.swift` | Runs when "Solve" is tapped. Marks the alarm ringing and opens the app. Shared with the widget. |
| `BrainAlarm/Intents/StopTappedIntent.swift` | Runs when the system Stop button is tapped. Marks ringing, silences that one alarm, opens the app. |
| `BrainAlarm/ViewModels/AlarmEditorModel.swift` | The save workflow and editor screen state. |
| `BrainAlarm/ViewModels/PuzzleModel.swift` | Problem, streak, and what happens on solve. |
| `BrainAlarm/Views/` | `AlarmEditorView`, `PuzzleView` (custom keypad), `PermissionDeniedView`. |
| `BrainAlarmWidgets/AlarmLiveActivity.swift` | Live Activity for the alarm. Required by AlarmKit; minimal on purpose. |
| `BrainAlarmTests/` | Unit tests with a mock alarm service and mock store. |

## The save workflow, in plain English

When you tap **Save** with the alarm enabled, `AlarmEditorModel.saveAlarm` does these steps in order.
If any step fails, the ones after it do not run, and you see a message that says which step failed.

1. **Validate** the setting (hour, minute, backup count and interval). Failure: "That alarm can't be saved: …".
2. **Ask for permission** if the system has never asked. If you declined earlier, stop here with "not allowed to schedule alarms".
3. **Cancel** any alarms a previous save created for this setting, so there are never two copies.
4. **Schedule the main alarm** with AlarmKit. Failure: "The alarm could not be scheduled."
5. **Schedule the backup chain** (fixed-time alarms after the main one). If any backup fails, the main alarm is cancelled again and you see the scheduling error.
6. **Save locally.** If this fails, every alarm just scheduled is cancelled and you see "was scheduled but could not be saved, so it was cancelled". You never end up with an alarm the app has forgotten about.
7. Only now does the screen say "Alarm scheduled."

The Save button is disabled while this runs, so a second tap does nothing.

**Test alarm in 60s** runs the same workflow on a separate one-shot setting with three backups one minute apart. Your real alarm is untouched.

## Permission behaviour

| State | What the app does |
|---|---|
| Not determined | On launch, and again on Save, the app asks the system to show the permission prompt. |
| Authorized | Everything works. Status row shows "Allowed". |
| Denied | The editor is replaced by a screen with an "Open Settings" button. Saving throws `permissionDenied`. |

## Stop, cancel, snooze

AlarmKit distinguishes these, and so does this app:

- **Stop** (`stopAlarm`): silences an alarm that is ringing right now. A repeating alarm stays scheduled for its next day; a one-shot alarm is deleted by the system.
- **Cancel** (`cancelAlarms`): removes alarms from the system entirely, whether or not they are ringing. Used when you disable the alarm, when you re-save it, and when the puzzle is solved.
- **Snooze**: does not exist here. The system's Stop button is turned into a "Solve" button (see below).

## How the backup chain works

AlarmKit always shows a system **Stop** button on the alert, and we cannot remove it. So:

1. When you save an alarm for time T, the app also schedules `backupAlarmCount` extra alarms (default 5) at T+1 min, T+2 min, … (default interval 60 s). They have escalating titles like "Nice try. Solve it."
2. Tapping **Stop** runs `StopTappedIntent`: it silences that one alarm, records that an alarm is ringing, and opens the app straight into the puzzle. The backups stay scheduled.
3. Tapping **Solve** runs `OpenPuzzleIntent`: same thing without the stop.
4. If you kill the app, the flags live in App Group storage, so the next launch lands on the puzzle again.
5. Only a solved puzzle (the difficulty's streak of correct answers) stops the ringing alarm and cancels every backup.
6. For a repeating alarm, AlarmKit repeats the main alarm on its own, and the app immediately schedules a fresh backup chain for the next occurrence.

Wrong answers give you a new problem and reset the streak. The puzzle screen cannot be swiped away.

## Things to double-check on the first compile

Every AlarmKit signature was checked against Apple's documentation, with two exceptions that could not be confirmed offline and may need a one-line fix:

- `AlertConfiguration.AlertSound.named(_:)` for a custom sound file (only used when `soundFileName` is set).
- `Alarm.State.alerting`, used in `AlarmService.handleAlarmUpdate` to notice an alarm ringing while the app is open.

Also note that `AlarmPresentation.Alert(title:stopButton:…)` is deprecated; the app uses `Alert(title:secondaryButton:secondaryButtonBehavior:)`, where the Stop control is provided by the system.
