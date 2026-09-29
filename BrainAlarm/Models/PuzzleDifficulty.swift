import Foundation

/// How hard the wake-up puzzle is, and how many correct answers in a row are needed.
enum PuzzleDifficulty: String, Codable, CaseIterable, Identifiable {
    /// 2-digit + 2-digit. One correct answer ends the alarm.
    case easy

    /// 2-digit × 1-digit, or three operands. Two correct answers in a row.
    case medium

    /// 2-digit × 2-digit, or mixed operators with precedence. Three correct answers in a row.
    case hard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }

    /// Number of consecutive correct answers required before the alarm chain is cancelled.
    var requiredCorrectAnswers: Int {
        switch self {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }
}
