import SwiftUI

/// Full-screen gate shown while an alarm is ringing. Cannot be swiped away.
struct PuzzleView: View {
    @Bindable var model: PuzzleModel
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if model.isSolved {
                goodMorningView
            } else {
                puzzleContent
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: Solving

    private var puzzleContent: some View {
        VStack(spacing: 24) {
            Text("Solve to silence the alarm")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(model.correctStreak) of \(model.requiredCorrectAnswers) correct")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(model.currentProblem.prompt)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .modifier(ShakeEffect(shakes: CGFloat(model.wrongAnswerCount)))
                .animation(.default, value: model.wrongAnswerCount)

            Text(model.typedAnswer.isEmpty ? " " : model.typedAnswer)
                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                .frame(height: 50)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            keypad

            Button {
                Task {
                    await model.submitAnswer()
                }
            } label: {
                Text("Submit")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.typedAnswer.isEmpty || model.typedAnswer == "-")
            .padding(.horizontal)
        }
        .padding(.top, 40)
    }

    /// Large custom keypad so the system keyboard never covers the problem.
    private var keypad: some View {
        let rows: [[KeypadKey]] = [
            [.digit(1), .digit(2), .digit(3)],
            [.digit(4), .digit(5), .digit(6)],
            [.digit(7), .digit(8), .digit(9)],
            [.negative, .digit(0), .delete],
        ]

        return VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 12) {
                    ForEach(rows[rowIndex]) { key in
                        keypadButton(key)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func keypadButton(_ key: KeypadKey) -> some View {
        Button {
            switch key {
            case .digit(let digit):
                model.appendDigit(digit)
            case .negative:
                model.toggleNegative()
            case .delete:
                model.deleteLastCharacter()
            }
        } label: {
            Text(key.label)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: Solved

    private var goodMorningView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
            Text("Good morning")
                .font(.largeTitle.weight(.bold))
            Text("The alarm and its backups are cancelled.")
                .foregroundStyle(.secondary)
            Button("Done") {
                onFinished()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
    }
}

// MARK: Supporting types

private enum KeypadKey: Identifiable {
    case digit(Int)
    case negative
    case delete

    var id: String { label }

    var label: String {
        switch self {
        case .digit(let digit): return String(digit)
        case .negative: return "±"
        case .delete: return "⌫"
        }
    }
}

/// Horizontal shake driven by a counter: each increment plays one shake.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let amplitude: CGFloat = 12
        let offset = amplitude * sin(shakes * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
