import SwiftUI

struct SessionsListView: View {
    @EnvironmentObject var transcriptStore: TranscriptStore
    @State private var selectedSessionID: UUID?
    @State private var geminiAPIKey = KeychainHelper.loadGeminiAPIKey() ?? ""

    var body: some View {
        HSplitView {
            sessionsList
                .frame(minWidth: 240, idealWidth: 280)

            sessionDetail
                .frame(minWidth: 550)
        }
        .navigationTitle("جلسات و یادداشت‌ها")
        .onAppear {
            geminiAPIKey = KeychainHelper.loadGeminiAPIKey() ?? ""
            if selectedSessionID == nil {
                selectedSessionID = transcriptStore.sessions.first?.id
            }
        }
    }

    private var sessionsList: some View {
        List(selection: $selectedSessionID) {
            ForEach(transcriptStore.sessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        if session.summary != nil {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        }
                    }

                    if let calEvent = session.calendarEventTitle {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(calEvent)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.blue)
                    }

                    HStack {
                        Text("\(session.wordCount) کلمه")
                        Text("•")
                        Text(session.createdAt, style: .date)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(session.id)
            }
        }
    }

    @ViewBuilder
    private var sessionDetail: some View {
        if let sessionID = selectedSessionID,
           let session = transcriptStore.sessions.first(where: { $0.id == sessionID }) {
            SessionDetailView(session: session, geminiAPIKey: geminiAPIKey)
        } else {
            ContentUnavailableView(
                "جلسه‌ای انتخاب نشده",
                systemImage: "doc.text",
                description: Text("یک جلسه را از ستون کناری انتخاب کنید.")
            )
        }
    }
}

struct SessionDetailView: View {
    let session: TranscriptionSession
    let geminiAPIKey: String

    @EnvironmentObject var transcriptStore: TranscriptStore

    @State private var selectedTemplate: SummaryTemplate = .general
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var isExtractingActions = false
    @State private var actionError: String?
    @State private var exportMessage: String?

    // Chat with meeting state
    @State private var chatQuery = ""
    @State private var isAnswering = false
    @State private var chatAnswers: [(question: String, answer: String)] = []
    @State private var chatError: String?

    // Editable title
    @State private var isEditingTitle = false
    @State private var editedTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                exportSection
                audioSection
                summarySection
                actionItemsSection
                chatSection
                transcriptSection
            }
            .padding(18)
        }
        .onAppear {
            editedTitle = session.title
        }
        .onChange(of: session.id) { _, _ in
            editedTitle = session.title
            chatAnswers.removeAll()
            summaryError = nil
            actionError = nil
            chatError = nil
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if isEditingTitle {
                    HStack {
                        TextField("عنوان جلسه", text: $editedTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                        Button("ذخیره") {
                            transcriptStore.updateTitle(editedTitle, for: session.id)
                            isEditingTitle = false
                        }
                    }
                } else {
                    HStack {
                        Text(session.title)
                            .font(.title2.bold())
                        Button {
                            editedTitle = session.title
                            isEditingTitle = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(session.wordCount) کلمه")
                    Text("•")
                    Text(session.createdAt.formatted())
                    if let cal = session.calendarEventTitle {
                        Text("•")
                        Label(cal, systemImage: "calendar")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                transcriptStore.deleteSession(session)
            } label: {
                Label("حذف", systemImage: "trash")
            }
        }
    }

    private var exportSection: some View {
        GroupBox("اشتراک‌گذاری و خروجی") {
            HStack(spacing: 12) {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        exportSession(format: format)
                    } label: {
                        Label(format.label, systemImage: format == .pdf ? "doc.richtext" : "doc.text")
                    }
                    .disabled(session.fullText.isEmpty)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.formattedDialogue, forType: .string)
                    exportMessage = "گفتگو در کلیپ‌بورد کپی شد"
                } label: {
                    Label("کپی متن کامل", systemImage: "doc.on.doc")
                }
                .disabled(session.fullText.isEmpty)

                Spacer()

                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        if let audioURL = session.audioFileURL {
            GroupBox("فایل صوتی جلسه") {
                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(audioURL)
                    } label: {
                        Label("پخش صدا", systemImage: "play.circle.fill")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                    } label: {
                        Label("نمایش در Finder", systemImage: "folder")
                    }

                    Spacer()

                    if let size = try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64 {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var summarySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("خلاصه هوشمند با Gemini", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    Spacer()

                    Picker("قالب", selection: $selectedTemplate) {
                        ForEach(SummaryTemplate.allCases) { tmpl in
                            Label(tmpl.title, systemImage: tmpl.icon).tag(tmpl)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)

                    Button {
                        Task { await generateSummary() }
                    } label: {
                        if isSummarizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("خلاصه‌سازی")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isSummarizing || session.fullText.isEmpty || geminiAPIKey.isEmpty)
                }

                if geminiAPIKey.isEmpty {
                    Text("برای استفاده از خلاصه‌سازی هوشمند، ابتدا کلید API جمینای را در بخش تنظیمات وارد کنید.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = summaryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let summary = session.summary {
                    Text(summary)
                        .textSelection(.enabled)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                } else {
                    Text("هنوز خلاصه‌ای تولید نشده است. قالب مورد نظر را انتخاب و دکمه خلاصه‌سازی را بزنید.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var actionItemsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("اقدامات بعدی و وظایف (Action Items)", systemImage: "checklist")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    Spacer()

                    if !session.actionItems.isEmpty {
                        Button {
                            copyActionItemsToClipboard()
                        } label: {
                            Label("کپی وظایف", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    Button {
                        Task { await extractActionItems() }
                    } label: {
                        if isExtractingActions {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("استخراج خودکار", systemImage: "sparkles")
                        }
                    }
                    .disabled(isExtractingActions || session.fullText.isEmpty || geminiAPIKey.isEmpty)
                }

                if let error = actionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if session.actionItems.isEmpty {
                    Text("هیچ اقدامی ثبت نشده است. می‌توانید با دکمه «استخراج خودکار» وظایف را توسط هوش مصنوعی استخراج کنید.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(session.actionItems) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    transcriptStore.toggleActionItem(item.id, in: session.id)
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                Text(item.text)
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                    .font(.callout)

                                if let assignee = item.assignee {
                                    Text(assignee)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(4)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var chatSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("پرسش و پاسخ از این جلسه", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .foregroundStyle(.teal)

                HStack {
                    TextField("مثلاً: درباره زمان تحویل چه تصمیمی گرفته شد؟", text: $chatQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await askQuestion() }
                        }

                    Button {
                        Task { await askQuestion() }
                    } label: {
                        if isAnswering {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("بپرس")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(isAnswering || chatQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || geminiAPIKey.isEmpty)
                }

                if let error = chatError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !chatAnswers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(chatAnswers.indices, id: \.self) { idx in
                            let pair = chatAnswers[idx]
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("پرسش: \(pair.question)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                Text(pair.answer)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(8)
                            .background(Color.teal.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var transcriptSection: some View {
        GroupBox("رونوشت کامل جلسه (تفکیک گویندگان)") {
            VStack(alignment: .leading, spacing: 10) {
                if !session.segments.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.segments) { segment in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: segment.speaker.icon)
                                            .font(.caption2)
                                        Text(segment.speaker.displayName)
                                            .font(.caption.bold())
                                    }
                                    .foregroundStyle(speakerColor(segment.speaker))

                                    Text(segment.formattedTime)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(width: 100, alignment: .leading)

                                Text(segment.text)
                                    .textSelection(.enabled)
                                    .font(.body)
                                    .lineSpacing(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Divider()
                        }
                    }
                } else {
                    Text(session.fullText.isEmpty ? "متنی در این جلسه وجود ندارد." : session.fullText)
                        .textSelection(.enabled)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func speakerColor(_ speaker: SpeakerType) -> Color {
        switch speaker {
        case .user: return .blue
        case .system: return .orange
        case .unknown: return .secondary
        }
    }

    private func exportSession(format: ExportFormat) {
        exportMessage = nil
        do {
            if let url = try ExportService.export(session: session, format: format) {
                exportMessage = "ذخیره شد: \(url.lastPathComponent)"
            }
        } catch {
            exportMessage = nil
            summaryError = error.localizedDescription
        }
    }

    private func generateSummary() async {
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }

        do {
            let summary = try await GeminiService.summarize(
                text: session.formattedDialogue,
                apiKey: geminiAPIKey,
                template: selectedTemplate
            )
            transcriptStore.setSummary(summary, for: session.id)
        } catch {
            summaryError = error.localizedDescription
        }
    }

    private func extractActionItems() async {
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

    private func askQuestion() async {
        let q = chatQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        isAnswering = true
        chatError = nil
        defer { isAnswering = false }

        do {
            let ans = try await GeminiService.chatWithMeeting(
                question: q,
                transcript: session.formattedDialogue,
                summary: session.summary,
                apiKey: geminiAPIKey
            )
            chatAnswers.append((question: q, answer: ans))
            chatQuery = ""
        } catch {
            chatError = error.localizedDescription
        }
    }

    private func copyActionItemsToClipboard() {
        let lines = session.actionItems.map { item in
            let check = item.isCompleted ? "[x]" : "[ ]"
            let assignee = item.assignee.map { " (@\($0))" } ?? ""
            return "\(check) \(item.text)\(assignee)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines, forType: .string)
        exportMessage = "وظایف در کلیپ‌بورد کپی شد"
    }
}
