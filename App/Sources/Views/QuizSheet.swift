import NotabilityCore
import SwiftUI

/// Phase 12: quiz generated from a record's transcript + typed notes.
/// Provider is a stub by default (AppProviders.quiz).
struct QuizSheet: View {
    let store: NotabilityStore
    let recordID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var quiz: Quiz?
    @State private var selected: [Int: Int] = [:]
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if failed {
                    ContentUnavailableView("Couldn't generate a quiz", systemImage: "exclamationmark.triangle",
                                           description: Text("Configure a DeepInfra key in Settings and try again."))
                } else if let quiz {
                    List(Array(quiz.questions.enumerated()), id: \.offset) { index, question in
                        Section {
                            Text(question.question)
                                .fontWeight(.semibold)
                            ForEach(Array(question.choices.enumerated()), id: \.offset) { c, choice in
                                Button {
                                    selected[index] = c
                                } label: {
                                    HStack {
                                        Text(choice)
                                        Spacer()
                                        if selected[index] == c {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                            }
                            if let chosen = selected[index] {
                                Text(chosen == question.answerIndex ? "Correct" : "Correct answer: \(question.choices[question.answerIndex])")
                                    .foregroundStyle(chosen == question.answerIndex ? .green : .red)
                                Text(question.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    ProgressView("Generating quiz…")
                }
            }
            .navigationTitle("Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await generate() }
        }
    }

    private func generate() async {
        let transcriptText = ((try? store.transcript(for: recordID))?.segments.map(\.text).joined(separator: " ") ?? "")
        let notes = ((try? store.blocks(in: recordID)) ?? []).compactMap { block -> String? in
            if case .text(let p) = block.payload, !p.text.isEmpty { return p.text }
            return nil
        }.joined(separator: "\n")
        if let result = try? await AppProviders.shared.quiz.generateQuiz(transcript: transcriptText, notes: notes) {
            quiz = result
        } else {
            failed = true
        }
    }
}
