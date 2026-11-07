import SwiftUI
import AppKit

struct SessionActionItemsTabView: View {
    let session: TranscriptionSession
    let geminiAPIKey: String
    let onCopy: (String, String) -> Void

    @EnvironmentObject var transcriptStore: TranscriptStore
    @State private var isExtractingActions = false
    @State private var actionError: String?
    @State private var newActionItemText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header Bar
                HStack(spacing: 12) {
                    Button {
                        Task { await extractActionItems() }
                    } label: {
                        if isExtractingActions {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(L10n.tr(.extracting))
                            }
                        } else {
                            Label(L10n.tr(.extractActionItems), systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isExtractingActions || session.fullText.isEmpty || geminiAPIKey.isEmpty)

                    if !session.actionItems.isEmpty {
                        Button {
                            copyActionItemsToClipboard()
                        } label: {
                            Label(L10n.tr(.copyActionItems), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        let doneCount = session.actionItems.filter(\.isCompleted).count
                        Text(L10n.tr(.tasksProgress(doneCount, session.actionItems.count)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Spacer()
                    }
                }

                if geminiAPIKey.isEmpty {
                    apiKeyBanner
                }

                if let error = actionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Add Task Field
                HStack(spacing: 8) {
                    TextField(L10n.tr(.addTaskPlaceholder), text: $newActionItemText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addManualTask() }

                    Button {
                        addManualTask()
                    } label: {
                        Label(L10n.tr(.add), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(newActionItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Task Items List (Apple Reminders Style)
                if session.actionItems.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.tr(.actionItemsTitle), systemImage: "checklist")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    } description: {
                        Text(L10n.tr(.noActionItemsYet))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(session.actionItems) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    transcriptStore.toggleActionItem(item.id, in: session.id)
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                Text(item.text)
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                    .font(.body)

                                Spacer()

                                if let assignee = item.assignee, !assignee.isEmpty {
                                    Text("@\(assignee)")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }

                                Button {
                                    transcriptStore.deleteActionItem(item.id, from: session.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .help(L10n.tr(.delete))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(20)
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

    private func addManualTask() {
        let trimmed = newActionItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = MeetingActionItem(text: trimmed, isCompleted: false, assignee: nil)
        transcriptStore.addActionItem(item, to: session.id)
        newActionItemText = ""
    }

    private func copyActionItemsToClipboard() {
        let lines = session.actionItems.map { item in
            let check = item.isCompleted ? "[x]" : "[ ]"
            let assignee = item.assignee.map { " (@\($0))" } ?? ""
            return "\(check) \(item.text)\(assignee)"
        }.joined(separator: "\n")

        onCopy(lines, L10n.tr(.tasksCopied))
    }

    private func extractActionItems() async {
        guard !geminiAPIKey.isEmpty else { return }
        isExtractingActions = true
        actionError = nil
        defer { isExtractingActions = false }

        do {
            let items = try await GeminiService.extractActionItems(
                text: session.formattedDialogue,
                apiKey: geminiAPIKey
            )
            transcriptStore.setActionItems(items, for: session.id)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
