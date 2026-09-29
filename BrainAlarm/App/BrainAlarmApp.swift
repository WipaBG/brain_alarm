import SwiftUI

@main
struct BrainAlarmApp: App {
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView(router: router)
        }
    }
}

/// Chooses between the editor and the permission screen, and lays the puzzle over both when needed.
struct RootView: View {
    @Bindable var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if router.permissionState == .denied {
                PermissionDeniedView()
            } else {
                AlarmEditorView(model: router.editorModel)
            }
        }
        .task {
            await router.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Coming back to the foreground (including after a Stop tap) re-checks the flags.
            if newPhase == .active {
                router.refreshPuzzleVisibility()
            }
        }
        .fullScreenCover(item: $router.activePuzzleModel) { puzzleModel in
            PuzzleView(model: puzzleModel) {
                router.dismissPuzzle()
            }
        }
    }
}
