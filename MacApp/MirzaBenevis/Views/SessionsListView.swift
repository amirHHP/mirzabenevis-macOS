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

    // Diarization & Attendees state
    @State private var isDiarizing = false
    @State private var diarizeError: String?
    @State private var diarizeSuccess: String?
    @State private var newAttendeeName = ""
    @State private var activeEditingSegment: TranscriptSegment?

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
                speakersAndAttendeesSection
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
            diarizeError = nil
            diarizeSuccess = nil
            newAttendeeName = ""
            activeEditingSegment = nil
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

    private var speakersAndAttendeesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("گویندگان و تفکیک هوشمند", systemImage: "person.2.fill")
                        .font(.headline)
                        .foregroundStyle(.indigo)

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            runVoiceEmbeddingClustering()
                        } label: {
                            Label("تفکیک صوتی آفلاین (Embeddings)", systemImage: "waveform.badge.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .disabled(session.segments.isEmpty)

                        Button {
                            Task { await runAIDiarization() }
                        } label: {
                            if isDiarizing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("تفکیک هوشمند با Gemini", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .disabled(isDiarizing || session.segments.isEmpty || geminiAPIKey.isEmpty)
                    }
                }

                if geminiAPIKey.isEmpty {
                    Text("برای تفکیک هوشمند گویندگان با هوش مصنوعی، ابتدا کلید API جمینای را در بخش تنظیمات وارد کنید.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = diarizeError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let success = diarizeSuccess {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("حاضران در جلسه (برای کمک به دقت تفکیک و نام‌گذاری سریع):")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("نام فرد حاضر (مثلاً: رضا، سارا، مهندس تقوی)...", text: $newAttendeeName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                            .onSubmit {
                                addAttendee()
                            }

                        Button {
                            addAttendee()
                        } label: {
                            Label("افزودن", systemImage: "plus")
                        }
                        .disabled(newAttendeeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()
                    }

                    if !session.distinctSpeakers.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(session.distinctSpeakers, id: \.self) { speaker in
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(speakerColor(speaker))
                                        .frame(width: 8, height: 8)

                                    Text(speaker)
                                        .font(.caption.bold())

                                    if session.attendees.contains(speaker) {
                                        Button {
                                            transcriptStore.removeAttendee(speaker, from: session.id)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(speakerColor(speaker).opacity(0.12))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
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
                            HStack(alignment: .top, spacing: 10) {
                                Menu {
                                    Text("تغییر گوینده به:")
                                    ForEach(session.distinctSpeakers, id: \.self) { candidate in
                                        if candidate != segment.speakerDisplayName {
                                            Button(candidate) {
                                                transcriptStore.updateSegmentSpeaker(
                                                    segmentID: segment.id,
                                                    speakerName: candidate,
                                                    in: session.id
                                                )
                                            }
                                        }
                                    }

                                    Divider()

                                    Button("ویرایش نام / تغییر سراسری...") {
                                        activeEditingSegment = segment
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: segment.speaker.icon)
                                            .font(.caption2)
                                        Text(segment.speakerDisplayName)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 7))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(speakerColor(segment.speakerDisplayName).opacity(0.15))
                                    .foregroundStyle(speakerColor(segment.speakerDisplayName))
                                    .cornerRadius(6)
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 130, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(segment.text)
                                        .textSelection(.enabled)
                                        .font(.body)
                                        .lineSpacing(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(segment.formattedTime)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
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
        .sheet(item: $activeEditingSegment) { segment in
            SpeakerEditorSheet(
                segment: segment,
                session: session,
                onSave: { newName, applyGlobally in
                    if applyGlobally {
                        transcriptStore.renameSpeakerGlobally(
                            from: segment.speakerDisplayName,
                            to: newName,
                            in: session.id
                        )
                    } else {
                        transcriptStore.updateSegmentSpeaker(
                            segmentID: segment.id,
                            speakerName: newName,
                            in: session.id
                        )
                    }
                }
            )
        }
    }

    private func speakerColor(_ name: String) -> Color {
        if name == "شما" || name == AppSettings.userName {
            return .blue
        }
        if name == "جلسه" || name == "جلسه / طرف مقابل" {
            return .orange
        }
        let palette: [Color] = [.purple, .teal, .pink, .indigo, .green, .mint, .cyan]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
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

    private func runVoiceEmbeddingClustering() {
        let results = VoiceEmbeddingEngine.shared.cluster(segments: session.segments)
        if results.isEmpty {
            diarizeError = "داده‌های صوتی برای این جلسه موجود نیست یا مدت زمان دیالوگ‌ها برای استخراج بردار صوتی کافی نبوده است."
            diarizeSuccess = nil
        } else {
            transcriptStore.applyDiarization(assignments: results, to: session.id)
            let uniqueCount = Set(results.values).count
            diarizeSuccess = "تفکیک صوتی آفلاین (Voice Embeddings) با موفقیت انجام شد: \(uniqueCount) گروه صوتی بر اساس تن و ویژگی‌های آکوستیک تفکیک شدند."
            diarizeError = nil
        }
    }

    private func runAIDiarization() async {
        isDiarizing = true
        diarizeError = nil
        diarizeSuccess = nil
        defer { isDiarizing = false }

        do {
            let results = try await GeminiService.diarizeSpeakers(
                segments: session.segments,
                attendees: session.attendees,
                apiKey: geminiAPIKey
            )
            transcriptStore.applyDiarization(assignments: results, to: session.id)
            diarizeSuccess = "گویندگان جلسه با موفقیت تفکیک و نام‌گذاری شدند (\(results.count) بخش به‌روزرسانی شد)."
        } catch {
            diarizeError = "خطا در تفکیک گویندگان: \(error.localizedDescription)"
        }
    }

    private func addAttendee() {
        let trimmed = newAttendeeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcriptStore.addAttendee(trimmed, to: session.id)
        newAttendeeName = ""
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

struct SpeakerEditorSheet: View {
    let segment: TranscriptSegment
    let session: TranscriptionSession
    let onSave: (String, Bool) -> Void

    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(segment: TranscriptSegment, session: TranscriptionSession, onSave: @escaping (String, Bool) -> Void) {
        self.segment = segment
        self.session = session
        self.onSave = onSave
        _name = State(initialValue: segment.speakerDisplayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ویرایش نام گوینده")
                .font(.headline)

            Text("نام فعلی: \(segment.speakerDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("نام جدید گوینده...", text: $name)
                .textFieldStyle(.roundedBorder)

            if !session.distinctSpeakers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("انتخاب سریع از میان حاضران:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(session.distinctSpeakers, id: \.self) { candidate in
                            Button(candidate) {
                                name = candidate
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("انصراف", role: .cancel) {
                    dismiss()
                }

                Spacer()

                Button("فقط این بخش") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, false)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("تغییر در کل جلسه") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, true)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
