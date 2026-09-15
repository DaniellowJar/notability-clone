import NotabilityCore
import SwiftUI

/// Inline calculator block (Phase 7): evaluates the expression locally via
/// `ExpressionEvaluator`; when parsing fails or the math looks complex, a
/// "sparkles" button sends it to the Math OCR provider (stub by default).
struct CalcBlockView: View {
    @Bindable var session: CanvasSessionState
    let block: CanvasBlock

    @State private var solving = false

    private var expression: String { block.calcExpression ?? "" }
    private var result: String { block.calcResult ?? "" }
    private var localResult: String? { session.evaluate(expression) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("e.g. 300 x 2", text: Binding(
                get: { expression },
                set: { session.setCalcExpression(block.id, expression: $0) }
            ))
            .font(.system(size: 17, weight: .medium))
            .keyboardType(.numbersAndPunctuation)

            Divider()

            HStack(alignment: .center) {
                Text(displayResult)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(localResult != nil ? .primary : .secondary)
                Spacer()
                if localResult == nil && !expression.isEmpty {
                    Button(action: solve) {
                        Group {
                            if solving {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("calcSolve")
                }
            }
        }
        .padding(12)
        .frame(width: max(block.frame.size.width, 1))
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var displayResult: String {
        if !expression.isEmpty, let local = localResult { return local }
        return result
    }

    private func solve() {
        solving = true
        Task {
            // TODO(provider): stub by default; live DeepInfra vision provider
            // once Phase 13 onboarding stores an API key.
            let provider = AppProviders.shared.mathOCR
            if let outcome = try? await provider.solve(imagePNG: Data(), recognizedText: expression) {
                await MainActor.run {
                    session.setCalcResult(block.id, result: outcome.result.isEmpty ? outcome.latex : outcome.result)
                    solving = false
                }
            } else {
                await MainActor.run { solving = false }
            }
        }
    }
}
