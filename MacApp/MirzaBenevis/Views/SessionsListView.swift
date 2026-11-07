import SwiftUI
import AppKit

// MARK: - String Sanitizer Helper

func sanitizeTitle(_ raw: String) -> String {
    var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while t.hasPrefix("/") || t.hasPrefix("•") || t.hasPrefix("-") || t.hasPrefix("|") {
        t = String(t.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    while t.hasSuffix("/") || t.hasSuffix("•") || t.hasSuffix("-") || t.hasSuffix("|") {
        t = String(t.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return t.isEmpty ? L10n.tr(.newSession) : t
}

// MARK: - Sessions List View (Root)

struct SessionsListView: View {
    @EnvironmentObject var transcriptStore: TranscriptStore
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var selectedSessionID: UUID?
    @State private var searchText = ""
    @State private var geminiAPIKey = KeychainHelper.loadGeminiAPIKey() ?? ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            detailView
        }
        .navigationTitle(L10n.tr(.sessionsTitle))
        .environment(\.layoutDirection, langManager.layoutDirection)
        .onAppear {
            geminiAPIKey = KeychainHelper.loadGeminiAPIKey() ?? ""
            if selectedSessionID == nil {
                selectedSessionID = transcriptStore.sessions.first?.id
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))

                TextField(L10n.tr(.searchPlaceholder), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Sessions List
            if filteredSessions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(L10n.tr(.noSessionsFound))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedSessionID) {
                    ForEach(filteredSessions) { session in
                        SessionRowView(
                            session: session,
                            onDelete: {
                                transcriptStore.deleteSession(session)
                                if selectedSessionID == session.id {
                                    selectedSessionID = transcriptStore.sessions.first?.id
                                }
                            }
                        )
                        .tag(session.id)
                    }
                }
                .listStyle(.sidebar)
            }

            // Footer with count
            Divider()
            HStack {
                Text("\(filteredSessions.count) \(L10n.tr(.sessionsTitle).lowercased())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private var filteredSessions: [TranscriptionSession] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return transcriptStore.sessions
        }
        return transcriptStore.sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(trimmed) ||
            session.fullText.localizedCaseInsensitiveContains(trimmed) ||
            session.attendees.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) ||
            (session.calendarEventTitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let sessionID = selectedSessionID,
           let session = transcriptStore.sessions.first(where: { $0.id == sessionID }) {
            SessionDetailView(session: session, geminiAPIKey: geminiAPIKey)
                .id(session.id)
        } else {
            ContentUnavailableView {
                Label(L10n.tr(.noSessionSelected), systemImage: "doc.text")
                    .font(.title2)
            } description: {
                Text(L10n.tr(.noSessionDescription))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Session Row View (Sidebar)

struct SessionRowView: View {
    let session: TranscriptionSession
    let onDelete: () -> Void

    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title & Badges
            HStack(spacing: 6) {
                Text(sanitizeTitle(session.title))
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()

                if session.summary != nil {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.purple)
                }

                if !session.actionItems.isEmpty {
                    Image(systemName: "checklist")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.blue)
                }

                if session.audioFileURL != nil {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            // Calendar Event Pill (if any)
            if let calEvent = session.calendarEventTitle, !calEvent.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9))
                    Text(calEvent)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.accentColor)
            }

            // Date & Word Count
            HStack(spacing: 6) {
                Text(formatDate(session.createdAt))
                Text("•")
                Text("\(session.wordCount) \(L10n.tr(.words))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // Preview snippet
            if !previewSnippet.isEmpty {
                Text(previewSnippet)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                exportFormat(.pdf)
            } label: {
                Label(L10n.tr(.exportPDF), systemImage: "doc.richtext")
            }

            Button {
                exportFormat(.docx)
            } label: {
                Label(L10n.tr(.exportWord), systemImage: "doc.text")
            }

            Button {
                copyTranscript()
            } label: {
                Label(L10n.tr(.copyTranscript), systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(L10n.tr(.delete), systemImage: "trash")
            }
        }
    }

    private var previewSnippet: String {
        if let firstSeg = session.segments.first, !firstSeg.text.isEmpty {
            return firstSeg.text
        }
        return session.fullText
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = langManager.currentLanguage.locale
        timeFormatter.timeStyle = .short

        if calendar.isDateInToday(date) {
            return "\(L10n.tr(.today)), \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "\(L10n.tr(.yesterday)), \(timeFormatter.string(from: date))"
        } else {
            let df = DateFormatter()
            df.locale = langManager.currentLanguage.locale
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.formattedDialogue, forType: .string)
    }

    private func exportFormat(_ format: ExportFormat) {
        _ = try? ExportService.export(session: session, format: format)
    }
}

// MARK: - Detail Tabs Enum

enum DetailTab: String, CaseIterable, Identifiable {
    case transcript
    case summary
    case actionItems
    case chat

    var id: String { rawValue }

    func label(lang: AppLanguage) -> String {
        switch self {
        case .transcript: return L10n.tr(.tabTranscript, lang)
        case .summary: return L10n.tr(.tabSummary, lang)
        case .actionItems: return L10n.tr(.tabActionItems, lang)
        case .chat: return L10n.tr(.tabChat, lang)
        }
    }

    var icon: String {
        switch self {
        case .transcript: return "doc.text"
        case .summary: return "sparkles"
        case .actionItems: return "checklist"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Apple Segmented Tab Bar

struct AppleSegmentedTabBar: View {
    @Binding var selectedTab: DetailTab
    let session: TranscriptionSession
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 3) {
            ForEach(DetailTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(tabAccentColor(tab, isSelected: isSelected))

                        Text(tab.label(lang: language))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                        if tab == .summary && session.summary != nil {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 5, height: 5)
                        }

                        if tab == .actionItems && !session.actionItems.isEmpty {
                            Text("\(session.actionItems.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.12))
                                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color(nsColor: .controlColor) : Color.clear)
                            .shadow(color: isSelected ? Color.black.opacity(0.08) : Color.clear, radius: 2, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.secondary.opacity(0.18) : Color.clear, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func tabAccentColor(_ tab: DetailTab, isSelected: Bool) -> Color {
        guard isSelected else { return .secondary }
        switch tab {
        case .transcript: return .accentColor
        case .summary: return .purple
        case .actionItems: return .blue
        case .chat: return .teal
        }
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: TranscriptionSession
    let geminiAPIKey: String

    @EnvironmentObject var transcriptStore: TranscriptStore
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var selectedTab: DetailTab = .transcript
    @State private var toastMessage: String?
    @State private var showDeleteConfirm = false
    @State private var exportError: String?

    // Audio Player
    @StateObject private var audioPlayer = AudioPlayerService()
    @State private var scrubTime: Double? = nil

    // Editing Speaker Sheet
    @State private var activeEditingSegment: TranscriptSegment?

    // Inline title editing
    @State private var isEditingTitle = false
    @State private var editedTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerArea
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Audio Player Bar (Voice Memos style)
            if let audioURL = session.audioFileURL {
                SessionAudioPlayerBar(
                    audioURL: audioURL,
                    audioPlayer: audioPlayer,
                    scrubTime: $scrubTime
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            // Apple Segmented Tab Bar
            HStack {
                AppleSegmentedTabBar(
                    selectedTab: $selectedTab,
                    session: session,
                    language: langManager.currentLanguage
                )

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Divider()

            // Tab Content
            tabContentArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            toolbarItems
        }
        .confirmationDialog(
            L10n.tr(.deleteSessionConfirmTitle),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.tr(.delete), role: .destructive) {
                transcriptStore.deleteSession(session)
            }
            Button(L10n.tr(.cancel), role: .cancel) {}
        } message: {
            Text(L10n.tr(.deleteSessionConfirmMessage(sanitizeTitle(session.title))))
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
        .onAppear {
            editedTitle = sanitizeTitle(session.title)
            if let audioURL = session.audioFileURL {
                audioPlayer.load(url: audioURL)
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
        .onChange(of: session.id) { _, _ in
            audioPlayer.stop()
            scrubTime = nil
            if let audioURL = session.audioFileURL {
                audioPlayer.load(url: audioURL)
            }
            editedTitle = sanitizeTitle(session.title)
            activeEditingSegment = nil
            toastMessage = nil
        }
    }

    // MARK: - Header Area

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(alignment: .center, spacing: 10) {
                if isEditingTitle {
                    HStack(spacing: 8) {
                        TextField(L10n.tr(.meetingTitlePlaceholder), text: $editedTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2.bold())
                            .frame(maxWidth: 380)

                        Button(L10n.tr(.save)) {
                            transcriptStore.updateTitle(sanitizeTitle(editedTitle), for: session.id)
                            isEditingTitle = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(L10n.tr(.cancel)) {
                            editedTitle = sanitizeTitle(session.title)
                            isEditingTitle = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(sanitizeTitle(session.title))
                            .font(.system(.title2, design: .default, weight: .bold))
                            .lineLimit(1)

                        Button {
                            editedTitle = sanitizeTitle(session.title)
                            isEditingTitle = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr(.meetingTitlePlaceholder))
                    }
                }

                Spacer()

                // Toast banner if active
                if let toast = toastMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(toast)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                    .transition(.opacity)
                }
            }

            // Metadata Chips
            HStack(spacing: 12) {
                // Date & Time
                Label(session.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Word count
                Label("\(session.wordCount) \(L10n.tr(.words))", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Audio file size (if available)
                if let audioURL = session.audioFileURL,
                   let size = try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64 {
                    Label(ByteCountFormatter.string(fromByteCount: size, countStyle: .file), systemImage: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Calendar event chip
                if let cal = session.calendarEventTitle, !cal.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(cal)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.10))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                }

                Spacer()
            }
        }
    }

    // MARK: - Toolbar Items

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // Language Switcher (EN / FA)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        langManager.currentLanguage = lang
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.displayName)")
                            if langManager.currentLanguage == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(langManager.currentLanguage.shortLabel)
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .help(L10n.tr(.language))
        }

        // Share & Export Menu
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    exportSession(format: .pdf)
                } label: {
                    Label(L10n.tr(.exportPDF), systemImage: "doc.richtext")
                }
                .disabled(session.fullText.isEmpty)

                Button {
                    exportSession(format: .docx)
                } label: {
                    Label(L10n.tr(.exportWord), systemImage: "doc.text")
                }
                .disabled(session.fullText.isEmpty)

                Divider()

                Button {
                    copyToClipboard(session.formattedDialogue, toast: L10n.tr(.copiedToClipboard))
                } label: {
                    Label(L10n.tr(.copyTranscript), systemImage: "doc.on.doc")
                }
                .disabled(session.fullText.isEmpty)

                if let summary = session.summary, !summary.isEmpty {
                    Button {
                        copyToClipboard(summary, toast: L10n.tr(.summaryCopied))
                    } label: {
                        Label(L10n.tr(.copySummary), systemImage: "sparkles")
                    }
                }

                if !session.actionItems.isEmpty {
                    Button {
                        copyActionItemsToClipboard()
                    } label: {
                        Label(L10n.tr(.copyActionItems), systemImage: "checklist")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help(L10n.tr(.shareAndExport))
        }

        // Delete Session Button
        ToolbarItem(placement: .destructiveAction) {
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
            }
            .help(L10n.tr(.delete))
        }
    }

    // MARK: - Tab Content Area

    @ViewBuilder
    private var tabContentArea: some View {
        switch selectedTab {
        case .transcript:
            SessionTranscriptTabView(
                session: session,
                geminiAPIKey: geminiAPIKey,
                audioPlayer: audioPlayer,
                activeEditingSegment: $activeEditingSegment
            )
        case .summary:
            SessionSummaryTabView(
                session: session,
                geminiAPIKey: geminiAPIKey,
                onCopy: { text, toast in
                    copyToClipboard(text, toast: toast)
                }
            )
        case .actionItems:
            SessionActionItemsTabView(
                session: session,
                geminiAPIKey: geminiAPIKey,
                onCopy: { text, toast in
                    copyToClipboard(text, toast: toast)
                }
            )
        case .chat:
            SessionChatTabView(
                session: session,
                geminiAPIKey: geminiAPIKey,
                onCopy: { text, toast in
                    copyToClipboard(text, toast: toast)
                }
            )
        }
    }

    private func copyToClipboard(_ text: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            toastMessage = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if toastMessage == toast {
                    toastMessage = nil
                }
            }
        }
    }

    private func copyActionItemsToClipboard() {
        let lines = session.actionItems.map { item in
            let check = item.isCompleted ? "[x]" : "[ ]"
            let assignee = item.assignee.map { " (@\($0))" } ?? ""
            return "\(check) \(item.text)\(assignee)"
        }.joined(separator: "\n")

        copyToClipboard(lines, toast: L10n.tr(.tasksCopied))
    }

    private func exportSession(format: ExportFormat) {
        do {
            if let url = try ExportService.export(session: session, format: format) {
                withAnimation {
                    toastMessage = L10n.tr(.savedFile(url.lastPathComponent))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation { toastMessage = nil }
                }
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}
