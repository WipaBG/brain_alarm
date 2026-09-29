# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

BrainAlarm: a personal iOS alarm app built on AlarmKit. The alarm cannot be silenced for good until the user solves a short math puzzle. The full spec, data model, save workflow, and build order live in `plan.md`; read it before starting any step. This file only captures the rules that must hold across every change.

## Building and testing

The Xcode project is generated from `project.yml` with XcodeGen and is git-ignored. The source has been written but not yet compiled on a Mac; expect a first round of compiler fixes.

```sh
xcodegen generate
xcodebuild build -scheme BrainAlarm -destination 'generic/platform=iOS'
xcodebuild test  -scheme BrainAlarm -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -scheme BrainAlarm -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BrainAlarmTests/AlarmEditorModelTests
```

Before the first build replace `com.example` in `project.yml` and `BrainAlarm/Models/AppGroup.swift`, and set the signing team. Files compiled into both the app and the widget are listed under the widget target's `sources` in `project.yml`; add a shared file there, not by copying it.

## Environment

- iOS 26+ only, Swift + SwiftUI, Xcode 26. No cross-platform layer.
- AlarmKit needs a physical iPhone. Do not treat Simulator results as proof that an alarm rings.
- Verify every AlarmKit signature against `developer.apple.com/documentation/alarmkit`, Apple's sample "Scheduling an alarm with AlarmKit", and WWDC25 session 230 before writing it. Never guess parameter names.
- Two targets: the app and a Widget Extension `BrainAlarmWidgets` with Live Activities enabled (AlarmKit renders alarms as Live Activities, so the extension is mandatory). They share an App Group `group.com.<me>.brainalarm` for `UserDefaults`.

## Architecture rules

- **AlarmKit is confined to `Services/AlarmService.swift`** (and `AlarmConfigurationFactory.swift` if the builder grows). The only other file that imports AlarmKit is the widget's Live Activity. If you need an AlarmKit call somewhere else, add a method to `AlarmService` instead.
- **Views → models → service.** No scheduling logic inside a SwiftUI `body`. Views call `@MainActor` model methods; models call `AlarmService`.
- **Stop and cancel are different operations** in AlarmKit. Keep `stopAlarm(id:)` and `cancelAlarms(ids:)` as separate, thin wrappers. Never merge them into a `disableAlarm()`.
- **The system Stop button cannot be removed.** The defense is a backup-alarm chain of fixed-date alarms after the main one (`plan.md` §6). `StopTappedIntent` must never cancel the backups; only a solved puzzle cancels the chain.
- **Main alarm uses `Alarm.Schedule.relative`** (follows local time zone); **backups use `Alarm.Schedule.fixed(date)`** (exact instants). Don't swap these. A test alarm sets `fixedFireDate` and is the one exception.
- **`AlarmPresentation.Alert(title:stopButton:…)` is deprecated.** Use `Alert(title:secondaryButton:secondaryButtonBehavior:)`; the Stop control is system-provided. `plan.md` §4 predates this.
- **Screen models are created once** in `AppRouter` and handed to views. Never construct a model inside a SwiftUI `body`; it would reset on every render.
- **Local state is not truth.** `reconcileWithSystem()` reads `AlarmManager.shared.alarms` on launch and drops stored IDs that no longer exist. Don't trust an `isEnabled` flag alone.
- Long-running observation (`alarmUpdates`) has exactly one owning `Task` in `AlarmService`, cancelled on deinit.
- Add layers only when they solve a concrete problem. The app is small; keep it small.

## Error handling in alarm workflows

- No `try?` on scheduling or cancelling. No `try!`. No forced unwraps.
- All failures go through one `enum AlarmError: LocalizedError` with cases `permissionDenied`, `invalidInput(reason)`, `schedulingFailed(underlying)`, `storageFailed(underlying)`. The UI shows a different message per case.
- Scheduling and persistence are separate steps. If `AlarmStore.save` fails after scheduling succeeded, cancel the just-scheduled alarms and rethrow `storageFailed`. Never leave a ghost alarm behind a user-visible error.
- Show "Alarm scheduled" only after `schedule(...)` returns. Disable Save while `isSchedulingAlarm` is true.
- Permission: read `authorizationState`, request only when `.notDetermined`, throw `permissionDenied` on `.denied`.

## Code style

Readability is a requirement. A developer who doesn't know Swift should be able to find where permission is requested, where the alarm is scheduled, and what happens if either fails.

- Names describe intent: `alarmManager` not `mgr`, `requestAlarmPermissionIfNeeded()` not `checkAuth()`, `chainIntervalSeconds: 60` not `time: 300`, `isSchedulingAlarm` not `flag`.
- Named intermediate values, plain `if`/`switch`, explicit closure parameter names. No `$0` where a real name helps, no nested ternaries, no long method chains.
- Comments explain decisions, not syntax (for example, why a schedule is relative vs fixed). Never comment obvious lines.
- `PuzzleGenerator` takes an injectable RNG so it can be unit tested.

## Tests

- Unit: `PuzzleGenerator`, `AlarmConfigurationFactory` (schedule type per case, backup dates), and the save workflow against a mock `AlarmService` covering permission denied, scheduling failure, storage failure triggering cancel, and repeated Save taps.
- Manual on-device checklist is in `plan.md` §11. Use the editor's "Test alarm in 60s" button for iteration.

## Deliverables besides code

`README.md` is required: file map, the save workflow in plain English, permission behavior (undetermined / authorized / denied), what stop, cancel and snooze mean in this app, and how the backup chain works.
