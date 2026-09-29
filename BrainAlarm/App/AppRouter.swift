import Foundation
import Observation

/// Owns the long-lived services and screen models, and decides when the puzzle is on top.
///
/// The one rule: if `SessionState.needsPuzzle` is true, the puzzle covers everything.
@MainActor
@Observable
final class AppRouter {
    /// Non-nil while the puzzle is presented. The view presents it with `fullScreenCover(item:)`.
    var activePuzzleModel: PuzzleModel?

    private(set) var permissionState: AlarmPermissionState = .notDetermined
    private(set) var startupErrorMessage: String?

    let alarmService: AlarmService
    let alarmStore: AlarmStore
    let sessionState: SessionState

    /// Created once so the editor keeps its state across view updates.
    let editorModel: AlarmEditorModel

    /// Listens for in-process session changes (posted by intents and the service). Owned here.
    private var sessionChangesTask: Task<Void, Never>?

    init(
        alarmService: AlarmService = AlarmService(),
        alarmStore: AlarmStore = AlarmStore(),
        sessionState: SessionState = SessionState()
    ) {
        self.alarmService = alarmService
        self.alarmStore = alarmStore
        self.sessionState = sessionState
        self.editorModel = AlarmEditorModel(
            alarmService: alarmService,
            alarmStore: alarmStore,
            sessionState: sessionState
        )
    }

    deinit {
        sessionChangesTask?.cancel()
    }

    /// Called once from the root view. Order matters: permission, then reconcile, then observe.
    func start() async {
        do {
            try await alarmService.requestAlarmPermissionIfNeeded()
        } catch {
            // A denied permission is shown by the root view; nothing else to do here.
        }
        permissionState = alarmService.currentPermissionState()

        do {
            try alarmService.reconcileWithSystem(store: alarmStore)
        } catch {
            startupErrorMessage = error.localizedDescription
        }

        alarmService.startObservingAlarmUpdates()
        startObservingSessionChanges()
        refreshPuzzleVisibility()
    }

    /// Presents the puzzle if the session says an alarm is ringing and unsolved.
    /// Called on launch, on every foreground, and on every session change.
    func refreshPuzzleVisibility() {
        guard sessionState.needsPuzzle else {
            return
        }

        // Keep an unsolved puzzle as it is; replace a solved one if a new alarm started ringing.
        if let existingModel = activePuzzleModel, !existingModel.isSolved {
            return
        }

        activePuzzleModel = makePuzzleModel()
    }

    /// Called from the puzzle's "Done" button after the "Good morning" screen.
    func dismissPuzzle() {
        activePuzzleModel = nil
    }

    /// Builds the puzzle for the alarm that is ringing, using that alarm's difficulty.
    private func makePuzzleModel() -> PuzzleModel {
        var difficulty: PuzzleDifficulty = .medium

        if let ringingAlarmID = sessionState.ringingAlarmID {
            do {
                if let owningSetting = try alarmStore.loadSetting(owningAlarmID: ringingAlarmID) {
                    difficulty = owningSetting.difficulty
                }
            } catch {
                // Unreadable store: fall back to medium rather than block the puzzle.
                startupErrorMessage = error.localizedDescription
            }
        }

        return PuzzleModel(
            difficulty: difficulty,
            alarmService: alarmService,
            alarmStore: alarmStore,
            sessionState: sessionState
        )
    }

    private func startObservingSessionChanges() {
        if sessionChangesTask != nil {
            return
        }

        sessionChangesTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: SessionState.didChangeNotification)
            for await _ in notifications {
                guard let self else { return }
                self.refreshPuzzleVisibility()
            }
        }
    }
}
