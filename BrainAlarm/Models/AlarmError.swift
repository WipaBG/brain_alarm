import Foundation

/// Every way the alarm workflow can fail. The UI shows a different message for each case,
/// so a user (and a developer reading logs) can tell a permission problem from a storage problem.
enum AlarmError: LocalizedError {
    /// The user declined AlarmKit permission. The only fix is in Settings.
    case permissionDenied

    /// The alarm setting itself is unusable (for example, a repeat day list with an impossible time).
    case invalidInput(reason: String)

    /// AlarmKit refused to schedule the alarm. The system error is kept for logging.
    case schedulingFailed(underlying: Error)

    /// The alarm was scheduled, but we could not remember it locally. The caller must cancel it.
    case storageFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "BrainAlarm is not allowed to schedule alarms. Enable it in Settings."
        case .invalidInput(let reason):
            return "That alarm can't be saved: \(reason)"
        case .schedulingFailed(let underlying):
            return "The alarm could not be scheduled. \(underlying.localizedDescription)"
        case .storageFailed(let underlying):
            return "The alarm was scheduled but could not be saved, so it was cancelled. \(underlying.localizedDescription)"
        }
    }
}
