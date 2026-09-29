# PROJECT: BrainAlarm — puzzle-gated iOS alarm

## Goal
A personal iOS alarm app where the alarm cannot be silenced for good until the user solves a short mental task (math by default). Built on AlarmKit so it rings through Silent mode and Focus, like the system Clock.

## Hard constraints (read first)
- **iOS 26+ only, Swift + SwiftUI, Xcode 26.** No cross-platform layer.
- **AlarmKit always shows a system Stop button we cannot remove.** Mitigation is a backup-alarm chain (§6), not UI hacks.
- **Requires a physical iPhone to test.** Simulator support for AlarmKit is limited.
- **Verify all AlarmKit signatures** against `developer.apple.com/documentation/alarmkit`, Apple's sample "Scheduling an alarm with AlarmKit", and WWDC25 session 230 before writing code. Don't guess parameter names.
- **Readability is a requirement, not a nicety** (§0). A developer who doesn't know Swift should be able to find where permission is requested, where the alarm is scheduled, and what happens if either fails.

## 0. Code style & readability rules
Swift's own API guidelines prioritize clarity over brevity; follow them.

**Naming — describe the user's intention:**

| Avoid | Prefer |
|---|---|
| `mgr` | `alarmManager` |
| `handle()` | `scheduleAlarm()` |
| `checkAuth()` | `requestAlarmPermissionIfNeeded()` |
| `time: 300` | `chainIntervalSeconds: 60` |
| `flag` | `isSchedulingAlarm` |
| `process(data)` | `makeAlarmConfiguration(from: setting)` |
| `disableAlarm()` | separate `stopAlarm()`, `cancelAlarm()` (AlarmKit distinguishes these) |

**Structure:**
- Named intermediate values; plain `if`/`switch`; explicit closure parameter names. No `$0` where a real name helps, no nested ternaries, no long method chains.
- Keep all AlarmKit calls inside `AlarmService.swift` (+ `AlarmConfigurationFactory.swift` if the builder gets long). Nothing else imports AlarmKit except the widget's Live Activity.
- No scheduling logic inside a SwiftUI `body`. Views call model methods; models call the service.
- UI-facing mutable state lives on `@MainActor`. Long-running observation tasks (e.g. `alarmUpdates`) have one clear owner and a cancellation point.
- Add layers only when they solve a concrete problem. This app is small; keep it small.

**Errors:**
- No `try?` on scheduling or cancelling — it hides failures. No `try!`, no forced unwraps in alarm workflows.
- Define one `enum AlarmError: LocalizedError` with distinct cases: `permissionDenied`, `invalidInput(reason)`, `schedulingFailed(underlying)`, `storageFailed(underlying)`. The UI shows different messages for each.
- Show "Alarm scheduled" only after `schedule(...)` actually returns.
- Disable the Save button while `isSchedulingAlarm` is true.
- Scheduling and local persistence are separate steps. If saving locally fails after scheduling succeeded, cancel the just-scheduled alarm(s) and rethrow, so the user never sees an error while a ghost alarm remains.

**Comments — explain decisions, not syntax:**
```swift
// Relative schedule so 07:00 follows the user's local time zone (e.g. when travelling).
// Fixed schedule for backup alarms: they must fire at exact instants after the main alarm.
```
Never comment obvious lines like `let hour = 7`.

**README.md (required deliverable):** file map, the save workflow in plain English, permission behavior (undetermined / authorized / denied), what "stop", "cancel" and "snooze" mean in this app, and how the backup chain works.

## 1. Project setup
- iOS App project, SwiftUI lifecycle, bundle id `com.<me>.brainalarm`, deployment target iOS 26.0.
- **Widget Extension** target `BrainAlarmWidgets` with Live Activities enabled — AlarmKit renders the alarm as a Live Activity, so this is mandatory.
- Info.plist (app): `NSAlarmKitUsageDescription` = "BrainAlarm needs to schedule alarms that ring even in Silent mode." and `NSSupportsLiveActivities` = YES.
- App Group `group.com.<me>.brainalarm` for `UserDefaults` shared by app, widget, and intents.
- Shared types (`BrainAlarmMetadata`, constants) in a file added to both targets or a local Swift package.

## 2. Architecture / file map
```
BrainAlarm/
  App/
    BrainAlarmApp.swift             — entry; requests permission on launch; owns AlarmService
    AppRouter.swift                 — routes to PuzzleView when an alarm is ringing
  Models/
    AlarmSetting.swift              — persisted alarm: time, days, difficulty, chain config, IDs
    PuzzleDifficulty.swift          — easy / medium / hard
    BrainAlarmMetadata.swift        — conforms to AlarmMetadata (shared with widget)
    AlarmError.swift                — distinct failure cases (see §0)
  Services/
    AlarmService.swift              — the only place that calls AlarmKit: permission, schedule, stop, cancel, observe
    AlarmConfigurationFactory.swift — builds AlarmManager.AlarmConfiguration from an AlarmSetting
    AlarmStore.swift                — saves/loads AlarmSetting + scheduled IDs (App Group UserDefaults)
    PuzzleGenerator.swift           — makes problems, checks answers
    SessionState.swift              — App Group flags: isAlarmRinging, isPuzzleSolved
  Intents/
    OpenPuzzleIntent.swift          — LiveActivityIntent; openAppWhenRun = true
    StopTappedIntent.swift          — LiveActivityIntent for the system Stop button
  ViewModels/
    AlarmEditorModel.swift          — @MainActor; save workflow + screen state (isSchedulingAlarm, error)
    PuzzleModel.swift               — @MainActor; current problem, attempts, solve → stop chain
  Views/
    AlarmEditorView.swift           — time picker, days, difficulty, enable, "Test in 60s"
    PuzzleView.swift                — full-screen gate with custom keypad
    PermissionDeniedView.swift      — blocking screen with Settings deep link
BrainAlarmWidgets/
  AlarmLiveActivity.swift           — ActivityConfiguration for AlarmAttributes<BrainAlarmMetadata>
README.md
```

## 3. Data model
```swift
struct AlarmSetting: Codable, Identifiable {
    var id: UUID
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    var repeatDays: Set<Locale.Weekday>      // empty = one-shot
    var difficulty: PuzzleDifficulty
    var backupAlarmCount: Int = 5
    var backupIntervalSeconds: Int = 60
    var soundFileName: String?               // bundled .wav/.caf; nil = default
    var mainAlarmID: UUID?
    var backupAlarmIDs: [UUID] = []
}

enum PuzzleDifficulty: String, Codable, CaseIterable {
    case easy    // 2-digit + 2-digit, 1 correct answer required
    case medium  // 2-digit × 1-digit or 3 operands, 2 correct
    case hard    // 2-digit × 2-digit or mixed ops w/ precedence, 3 correct
}

struct BrainAlarmMetadata: AlarmMetadata {
    var isBackupAlarm: Bool
    var backupIndex: Int
}
```

## 4. The save workflow (AlarmEditorModel → AlarmService)
Written to read top-to-bottom:
```swift
/// Schedules the user's alarm plus its backup chain, then remembers it locally.
func saveAlarm(_ setting: AlarmSetting) async throws {
    try validate(setting)                                        // → AlarmError.invalidInput
    try await alarmService.requestAlarmPermissionIfNeeded()      // → AlarmError.permissionDenied
    try await alarmService.cancelExistingAlarms(for: setting)

    let mainConfiguration = configurationFactory.makeMainAlarmConfiguration(from: setting)
    let mainAlarmID = try await alarmService.scheduleAlarm(mainConfiguration)   // → .schedulingFailed

    let backupIDs = try await alarmService.scheduleBackupChain(for: setting)

    var savedSetting = setting
    savedSetting.mainAlarmID = mainAlarmID
    savedSetting.backupAlarmIDs = backupIDs
    do {
        try alarmStore.save(savedSetting)                       // → .storageFailed
    } catch {
        // Don't leave ghost alarms behind if we can't remember them.
        try await alarmService.cancelAlarms(ids: [mainAlarmID] + backupIDs)
        throw AlarmError.storageFailed(error)
    }
}
```
`AlarmService` responsibilities:
- `requestAlarmPermissionIfNeeded()` — reads `authorizationState`; requests only if `.notDetermined`; throws on `.denied`.
- `scheduleAlarm(_:)` — wraps `AlarmManager.shared.schedule(id:configuration:)`.
- `stopAlarm(id:)`, `cancelAlarms(ids:)` — thin, distinct wrappers.
- `observeAlarmUpdates()` — one owned `Task` iterating `AlarmManager.shared.alarmUpdates`; cancelled on deinit.
- `reconcileWithSystem()` — on launch, read `AlarmManager.shared.alarms` and drop stored IDs that no longer exist; a local `isEnabled` flag alone is not truth.

`AlarmConfigurationFactory` builds:
- Main alarm: `Alarm.Schedule.relative` (time of day + weekly repeat) — follows local time zone.
- Backup alarms: `Alarm.Schedule.fixed(date)` at T+1m, T+2m… — exact instants.
- `AlarmPresentation.Alert(title:, stopButton:, secondaryButton:, secondaryButtonBehavior: .custom)` with a "Solve" secondary button.
- `AlarmAttributes<BrainAlarmMetadata>(presentation:, metadata:, tintColor:)`.
- `AlarmManager.AlarmConfiguration(schedule:, attributes:, stopIntent: StopTappedIntent, secondaryIntent: OpenPuzzleIntent, sound:)`.

## 5. Puzzle gate (PuzzleView / PuzzleModel)
- Presented as `fullScreenCover` from the root when `SessionState.isAlarmRinging`; `interactiveDismissDisabled(true)`.
- Generated problem + large custom numeric keypad (no system keyboard).
- Correct answer → increment streak; when streak reaches the difficulty's requirement: set `isPuzzleSolved = true`, call `alarmService.stopAlarm(id:)` for the ringing alarm and `cancelAlarms(ids:)` for all backups, show a brief "Good morning" screen.
- Wrong answer → shake, generate a **new** problem, reset streak to 0.
- `PuzzleGenerator` takes an injectable RNG for unit tests.
- v2 puzzle types: retype a sentence exactly, sort 5 numbers, memory grid.

## 6. Stop-button defense (backup chain)
- Alongside the main alarm at T, schedule `backupAlarmCount` fixed alarms at T+n×interval, titles escalating ("Nice try. Solve it.").
- `StopTappedIntent.perform()`: set `isAlarmRinging = true`, do **not** cancel backups. With `openAppWhenRun = true`, tapping Stop launches the app straight into `PuzzleView` — Stop becomes a de-facto Solve button.
- Only a solved puzzle cancels the chain.
- On foreground: `isAlarmRinging && !isPuzzleSolved` → show puzzle.
- After solve, for repeating alarms: AlarmKit repeats the main alarm itself; the fixed-date backups must be re-created for the next occurrence.

## 7. Live Activity (widget target)
- `ActivityConfiguration(for: AlarmAttributes<BrainAlarmMetadata>.self)`.
- Lock Screen: title, time, `Button(intent: OpenPuzzleIntent())` labelled "Solve". Dynamic Island: minimal.
- Start with the smallest configuration that compiles and rings; polish last.

## 8. Alarm editor screen
Wheel time picker, weekday toggles, difficulty control, enable toggle, next-fire-time label, permission status, Save (disabled while scheduling), and **"Test alarm in 60s"** (one-shot, essential for dev iteration).

## 9. Edge cases
- Permission denied → `PermissionDeniedView` with Settings link.
- App killed while ringing → relaunch routes to puzzle via `SessionState`.
- Reboot → AlarmKit persists alarms; run `reconcileWithSystem()` on launch.
- Setting changed while backups pending → cancel all, reschedule.
- Solved during a backup alarm → still cancel everything.
- Time zone / DST → relative schedule for main, `Calendar.current` for backup dates.

## 10. Build order (each step compiles and runs on device)
1. App + widget extension; permission prompt; ring a default AlarmKit alarm 60s out.
2. "Solve" secondary button + `OpenPuzzleIntent` opens the app.
3. `PuzzleView` + `PuzzleGenerator`; solving calls `stopAlarm`.
4. Backup chain + cancel-on-solve.
5. `StopTappedIntent` with `openAppWhenRun`.
6. `AlarmEditorView` / `AlarmEditorModel` with the §4 save workflow, `AlarmError`, persistence, reconciliation.
7. Difficulty streaks, custom sound.
8. README.md, Live Activity polish, haptics.

## 11. Tests
- **Unit:** `PuzzleGenerator` (answers, difficulty ranges), `AlarmConfigurationFactory` (schedule type per case, backup dates), save workflow with a mock `AlarmService` covering: permission denied, scheduling failure, storage failure triggers cancel, repeated Save taps ignored.
- **Manual on device:** Silent + DND → rings; lock screen shows Stop + Solve; Stop → app opens to puzzle, backup rings 60s later; wrong answer → new problem; solve → `AlarmManager.shared.alarms` has only the repeating main; force-quit during ring → relaunch lands on puzzle; reboot → still scheduled; change time zone → main alarm follows local time.

## 12. Non-goals (v1)
No accounts, sync, Watch app, App Store submission, Android.
