import XCTest
@testable import BrainAlarm

final class PuzzleGeneratorTests: XCTestCase {
    func testEasyProblemAddsTwoTwoDigitNumbers() {
        var generator = PuzzleGenerator(randomSource: ScriptedRandomSource([47, 38]))

        let problem = generator.makeProblem(difficulty: .easy)

        XCTAssertEqual(problem.prompt, "47 + 38")
        XCTAssertEqual(problem.answer, 85)
    }

    func testMediumMultiplicationPath() {
        // First value 0 selects multiplication; then 23 × 7.
        var generator = PuzzleGenerator(randomSource: ScriptedRandomSource([0, 23, 7]))

        let problem = generator.makeProblem(difficulty: .medium)

        XCTAssertEqual(problem.prompt, "23 × 7")
        XCTAssertEqual(problem.answer, 161)
    }

    func testMediumThreeOperandPathCanBeNegative() {
        // First value 1 selects a + b − c; 10 + 10 − 99.
        var generator = PuzzleGenerator(randomSource: ScriptedRandomSource([1, 10, 10, 99]))

        let problem = generator.makeProblem(difficulty: .medium)

        XCTAssertEqual(problem.prompt, "10 + 10 − 99")
        XCTAssertEqual(problem.answer, -79)
    }

    func testHardPrecedencePathMultipliesBeforeAdding() {
        // First value 1 selects a + b × c; 50 + 3 × 4 = 62, not (50 + 3) × 4.
        var generator = PuzzleGenerator(randomSource: ScriptedRandomSource([1, 50, 3, 4]))

        let problem = generator.makeProblem(difficulty: .hard)

        XCTAssertEqual(problem.prompt, "50 + 3 × 4")
        XCTAssertEqual(problem.answer, 62)
    }

    func testHardMultiplicationUsesTwoDigitOperands() {
        var generator = PuzzleGenerator(randomSource: ScriptedRandomSource([0, 12, 34]))

        let problem = generator.makeProblem(difficulty: .hard)

        XCTAssertEqual(problem.prompt, "12 × 34")
        XCTAssertEqual(problem.answer, 408)
    }

    func testIsCorrectComparesAnswers() {
        let generator = PuzzleGenerator(randomSource: ScriptedRandomSource([]))
        let problem = MathProblem(prompt: "1 + 1", answer: 2)

        XCTAssertTrue(generator.isCorrect(2, for: problem))
        XCTAssertFalse(generator.isCorrect(3, for: problem))
    }

    func testSystemRandomStaysInsideDifficultyRanges() {
        var generator = PuzzleGenerator()

        for _ in 0..<200 {
            let easy = generator.makeProblem(difficulty: .easy)
            XCTAssertTrue((20...198).contains(easy.answer), "easy answer out of range: \(easy.answer)")

            let hard = generator.makeProblem(difficulty: .hard)
            XCTAssertTrue((14...9801).contains(hard.answer), "hard answer out of range: \(hard.answer)")
        }
    }
}
