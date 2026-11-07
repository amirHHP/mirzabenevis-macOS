import SwiftUI
import AppKit

struct SessionSummaryTabView: View {
    let session: TranscriptionSession
    let geminiAPIKey: String
    let onCopy: (String, String) -> Void

    @EnvironmentObject var transcriptStore: TranscriptStore
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var selectedTemplate: SummaryTemplate = .general
    @State private var isSummarizing = false
    @State private var summaryError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary Actions Bar
                HStack(spacing: 12) {
                    // Template Picker
                    Picker(L10n.tr(.template), selection: $selectedTemplate) {
                        ForEach(SummaryTemplate.allCases) { tmpl in
                            Label(tmpl.localizedTitle(for: langManager.currentLanguage), systemImage: tmpl.icon).tag(tmpl)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240)

                    // Generate Button
                    Button {
                        Task { await generateSummary() }
                    } label: {
                        if isSummarizing {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(L10n.tr(.summarizing))
                            }
                        } else {
                            Label(
                                session.summary == nil ? L10n.tr(.generateSummary) : L10n.tr(.regenerateSummary),
                                systemImage: "sparkles"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isSummarizing || session.fullText.isEmpty || geminiAPIKey.isEmpty)

                    if let summary = session.summary, !summary.isEmpty {
                        Button {
                            onCopy(summary, L10n.tr(.summaryCopied))
                        } label: {
                            Label(L10n.tr(.copySummary), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }

                // Missing API key warning
                if geminiAPIKey.isEmpty {
                    apiKeyBanner
                }

                if let error = summaryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Summary Content or Empty State
                if let summary = session.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(summary)
                            .textSelection(.enabled)
                            .font(.body)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                    )
                } else {
                    ContentUnavailableView {
                        Label(L10n.tr(.aiSummaryTitle), systemImage: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.purple)
                    } description: {
                        Text(L10n.tr(.noSummaryYet))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
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

    private func generateSummary() async {
        guard !geminiAPIKey.isEmpty else { return }
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }

        do {
            let summary = try await GeminiService.summarize(
                text: session.formattedDialogue,
                apiKey: geminiAPIKey,
                template: selectedTemplate,
                language: session.language ?? "fa"
            )
            transcriptStore.setSummary(summary, for: session.id)
        } catch {
            summaryError = error.localizedDescription
        }
    }
}
