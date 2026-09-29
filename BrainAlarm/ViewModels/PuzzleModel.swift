import Foundation
import Observation

/// The puzzle gate: hands out problems, counts the streak, and silences the alarm chain on success.
@MainActor
@Observable
final class PuzzleModel: Identifiable {
    /// Lets SwiftUI present the model with `fullScreenCover(item:)`.
    let id = UUID()

    private(set) var currentProblem: MathProblem
    private(set) var typedAnswer: String = ""
    private(set) var correctStreak: Int = 0
    let requiredCorrectAnswers: Int

    /// True once the streak is complete and the alarms are cancelled. The view shows "Good morning".
    private(set) var isSolved = false

    /// Incremented on every wrong answer; the view animates a shake when it changes.
    private(set) var wrongAnswerCount = 0

    var errorMessage: String?

    private var generator: PuzzleGenerator
    private let difficulty: PuzzleDifficulty
    private let alarmService: any AlarmScheduling
    private let alarmStore: any AlarmStoring
    private let sessionState: SessionState
    private let configurationFactory: AlarmConfigurationFactory

    private static let maximumAnswerDigits = 7

    init(
        difficulty: PuzzleDifficulty,
        alarmService: any AlarmScheduling,
        alarmStore: any AlarmStoring,
        sessionState: SessionState = SessionState(),
        configurationFactory: AlarmConfigurationFactory = AlarmConfigurationFactory(),
        generator: PuzzleGenerator = PuzzleGenerator()
    ) {
        self.difficulty = difficulty
        self.requiredCorrectAnswers = difficulty.requiredCorrectAnswers
        self.alarmService = alarmService
        self.alarmStore = alarmStore
        self.sessionState = sessionState
        self.configurationFactory = configurationFactory

        // Make the first problem with a local copy: `self` isn't usable until every property is set.
        var startingGenerator = generator
        self.currentProblem = startingGenerator.makeProblem(difficulty: difficulty)
        self.generator = startingGenerator
    }

    // MARK: Keypad

    func appendDigit(_ digit: Int) {
        let digitsOnly = typedAnswer.filter { character in character.isNumber }
        if digitsOnly.count >= PuzzleModel.maximumAnswerDigits {
            return
        }
        typedAnswer.append(String(digit))
    }

    func deleteLastCharacter() {
        if !typedAnswer.isEmpty {
            typedAnswer.removeLast()
        }
    }

    /// Some medium problems (a + b − c) have negative answers.
    func toggleNegative() {
        if typedAnswer.hasPrefix("-") {
            typedAnswer.removeFirst()
        } else {
            typedAnswer = "-" + typedAnswer
        }
    }

    // MARK: Answering

    func submitAnswer() async {
        guard let answer = Int(typedAnswer) else {
            return
        }

        if generator.isCorrect(answer, for: currentProblem) {
            await handleCorrectAnswer()
        } else {
            handleWrongAnswer()
        }
    }

    private func handleCorrectAnswer() async {
        correctStreak += 1
        typedAnswer = ""

        if correctStreak < requiredCorrectAnswers {
            currentProblem = generator.makeProblem(difficulty: difficulty)
            return
        }

        do {
            try await silenceAlarmChain()
            isSolved = true
        } catch {
            // The user solved it; tell them plainly why the alarm may still ring, and let them retry.
            errorMessage = error.localizedDescription
            correctStreak = requiredCorrectAnswers - 1
            currentProblem = generator.makeProblem(difficulty: difficulty)
        }
    }

    private func handleWrongAnswer() {
        wrongAnswerCount += 1
        correctStreak = 0
        typedAnswer = ""
        // A wrong answer always gets a new problem, so guessing repeatedly doesn't help.
        currentProblem = generator.makeProblem(difficulty: difficulty)
    }

    // MARK: Silencing the chain

    /// Stops the ringing alarm, cancels every backup, and prepares repeating alarms for next time.
    private func silenceAlarmChain() async throws {
        let systemIDs = try alarmService.scheduledAlarmIDs()

        if let ringingAlarmID = sessionState.ringingAlarmID, systemIDs.contains(ringingAlarmID) {
            try alarmService.stopAlarm(id: ringingAlarmID)
        }

        var settings = try alarmStore.loadAll()

        for index in settings.indices {
            var setting = settings[index]

            let backupsStillScheduled = setting.backupAlarmIDs.filter { backupID in
                systemIDs.contains(backupID)
            }
            try alarmService.cancelAlarms(ids: backupsStillScheduled)
            setting.backupAlarmIDs = []

            if setting.isRepeating && setting.isEnabled {
                // AlarmKit repeats the main alarm itself; the fixed-date backups must be re-created
                // for the next occurrence.
                if let nextFireDate = configurationFactory.nextMainFireDate(for: setting) {
                    setting.backupAlarmIDs = try await alarmService.scheduleBackupChain(
                        for: setting,
                        mainFireDate: nextFireDate
                    )
                }
            } else {
                // A one-shot main alarm is deleted by the system once stopped.
                setting.mainAlarmID = nil
                setting.isEnabled = false
            }

            settings[index] = setting
        }

        // Finished test alarms have no further use.
        settings.removeAll(where: { setting in setting.isTestAlarm && !setting.isEnabled })

        try alarmStore.saveAll(settings)
        sessionState.markPuzzleSolved()
    }
}
