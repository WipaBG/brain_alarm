import Foundation

/// A source of random integers. The app uses the system generator; tests use a scripted one
/// so problems are predictable.
protocol RandomSource {
    mutating func nextInt(in range: ClosedRange<Int>) -> Int
}

struct SystemRandomSource: RandomSource {
    private var generator = SystemRandomNumberGenerator()

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &generator)
    }
}

/// One arithmetic question and its single integer answer.
struct MathProblem: Equatable {
    /// What the user sees, e.g. "47 + 38".
    let prompt: String
    let answer: Int
}

/// Makes arithmetic problems for each difficulty and checks answers.
struct PuzzleGenerator {
    private var randomSource: any RandomSource

    init(randomSource: any RandomSource = SystemRandomSource()) {
        self.randomSource = randomSource
    }

    mutating func makeProblem(difficulty: PuzzleDifficulty) -> MathProblem {
        switch difficulty {
        case .easy:
            return makeEasyProblem()
        case .medium:
            return makeMediumProblem()
        case .hard:
            return makeHardProblem()
        }
    }

    func isCorrect(_ answer: Int, for problem: MathProblem) -> Bool {
        answer == problem.answer
    }

    // MARK: Difficulty levels

    /// 2-digit + 2-digit.
    private mutating func makeEasyProblem() -> MathProblem {
        let left = randomSource.nextInt(in: 10...99)
        let right = randomSource.nextInt(in: 10...99)
        return MathProblem(prompt: "\(left) + \(right)", answer: left + right)
    }

    /// Either 2-digit × 1-digit, or a + b − c with 2-digit operands.
    private mutating func makeMediumProblem() -> MathProblem {
        let useMultiplication = randomSource.nextInt(in: 0...1) == 0

        if useMultiplication {
            let left = randomSource.nextInt(in: 10...99)
            let right = randomSource.nextInt(in: 2...9)
            return MathProblem(prompt: "\(left) × \(right)", answer: left * right)
        }

        let first = randomSource.nextInt(in: 10...99)
        let second = randomSource.nextInt(in: 10...99)
        let third = randomSource.nextInt(in: 10...99)
        return MathProblem(prompt: "\(first) + \(second) − \(third)", answer: first + second - third)
    }

    /// Either 2-digit × 2-digit, or a + b × c where multiplication happens first.
    private mutating func makeHardProblem() -> MathProblem {
        let useMultiplication = randomSource.nextInt(in: 0...1) == 0

        if useMultiplication {
            let left = randomSource.nextInt(in: 10...99)
            let right = randomSource.nextInt(in: 10...99)
            return MathProblem(prompt: "\(left) × \(right)", answer: left * right)
        }

        let addend = randomSource.nextInt(in: 10...99)
        let factorA = randomSource.nextInt(in: 2...12)
        let factorB = randomSource.nextInt(in: 2...12)
        // Operator precedence is the point of this problem: the product is added, not the sum multiplied.
        return MathProblem(prompt: "\(addend) + \(factorA) × \(factorB)", answer: addend + factorA * factorB)
    }
}
