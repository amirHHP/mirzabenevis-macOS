import SwiftUI
import AppKit

struct ChatMessagePair: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct SessionChatTabView: View {
    let session: TranscriptionSession
    let geminiAPIKey: String
    let onCopy: (String, String) -> Void

    @State private var chatQuery = ""
    @State private var isAnswering = false
    @State private var chatAnswers: [ChatMessagePair] = []
    @State private var chatError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Suggested Prompts Chips
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr(.suggestedQuestions))
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 6) {
                            suggestedChip(L10n.tr(.suggestedQ1))
                            suggestedChip(L10n.tr(.suggestedQ2))
                            suggestedChip(L10n.tr(.suggestedQ3))
                        }
                    }

                    if geminiAPIKey.isEmpty {
                        apiKeyBanner
                    }

                    if let error = chatError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Chat messages thread
                    if chatAnswers.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.tr(.chatTitle), systemImage: "bubble.left.and.bubble.right")
                                .font(.title3)
                                .foregroundStyle(.teal)
                        } description: {
                            Text(L10n.tr(.chatEmptySubtitle))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(chatAnswers) { pair in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Question bubble
                                    HStack {
                                        Text(L10n.tr(.questionPrefix(pair.question)))
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }

                                    // Answer
                                    Text(pair.answer)
                                        .font(.body)
                                        .lineSpacing(4)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)

                                    // Copy Answer Button
                                    HStack {
                                        Spacer()
                                        Button {
                                            onCopy(pair.answer, L10n.tr(.answerCopied))
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.on.doc")
                                                Text(L10n.tr(.copyAnswer))
                                            }
                                            .font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .padding(14)
                                .background(Color.teal.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.teal.opacity(0.15), lineWidth: 0.5)
                                )
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Bottom Prompt Bar
            HStack(spacing: 10) {
                TextField(L10n.tr(.chatPlaceholder), text: $chatQuery)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .onSubmit {
                        Task { await askQuestion() }
                    }

                Button {
                    Task { await askQuestion() }
                } label: {
                    if isAnswering {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isAnswering || chatQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || geminiAPIKey.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var apiKeyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            Text(L10n.tr(.apiKeyRequiredBanner))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(L10n.tr(.openSettings)) {
                if let url = URL(string: "mirzabenevis://settings") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func suggestedChip(_ text: String) -> some View {
        Button {
            chatQuery = text
            Task { await askQuestion() }
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func askQuestion() async {
        let q = chatQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !geminiAPIKey.isEmpty else { return }

        isAnswering = true
        chatError = nil
        let targetQuestion = q
        chatQuery = ""
        defer { isAnswering = false }

        do {
            let answer = try await GeminiService.chatWithMeeting(
                question: targetQuestion,
                transcript: session.formattedDialogue,
                summary: session.summary,
                apiKey: geminiAPIKey
            )
            chatAnswers.append(ChatMessagePair(question: targetQuestion, answer: answer))
        } catch {
            chatError = error.localizedDescription
        }
    }
}
