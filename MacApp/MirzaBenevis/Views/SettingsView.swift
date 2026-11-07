import SwiftUI

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case model
    case gemini
    case audio
    case calendar

    var id: String { rawValue }

    func label(lang: AppLanguage) -> String {
        switch self {
        case .general: return L10n.tr(.settingsGeneral, lang)
        case .model: return L10n.tr(.settingsModel, lang)
        case .gemini: return L10n.tr(.settingsGemini, lang)
        case .audio: return L10n.tr(.settingsAudio, lang)
        case .calendar: return L10n.tr(.settingsCalendar, lang)
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .model: return "waveform.badge.mic"
        case .gemini: return "sparkles"
        case .audio: return "speaker.wave.2"
        case .calendar: return "calendar"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var updateManager: UpdateManager
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var langManager = LanguageManager.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var appLanguage = AppSettings.appLanguage
    @State private var geminiAPIKey = KeychainHelper.loadGeminiAPIKey() ?? ""
    @State private var customHost = AppSettings.geminiCustomHost
    @State private var showKey = false
    @State private var savedKey = false
    @State private var selectedModel = AppSettings.whisperModelSize
    @State private var useGPU = AppSettings.useGPU
    @State private var userName = AppSettings.userName

    var body: some View {
        VStack(spacing: 0) {
            // Top Segmented Tab Bar
            tabBarHeader
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            // Active Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .model:
                        modelTab
                    case .gemini:
                        geminiTab
                    case .audio:
                        audioTab
                    case .calendar:
                        calendarTab
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 540, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.layoutDirection, langManager.layoutDirection)
        .navigationTitle(L10n.tr(.settingsTitle))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.tr(.close)) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Top Tab Bar

    private var tabBarHeader: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = selectedTab == tab

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(tabIconColor(tab, isSelected: isSelected))

                        Text(tab.label(lang: langManager.currentLanguage))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    .padding(.horizontal, 11)
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
            Spacer()
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func tabIconColor(_ tab: SettingsTab, isSelected: Bool) -> Color {
        guard isSelected else { return .secondary }
        switch tab {
        case .general: return .blue
        case .model: return .indigo
        case .gemini: return .purple
        case .audio: return .cyan
        case .calendar: return .red
        }
    }

    // MARK: - Tab 1: General & Updates

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Language Card
            settingsCard(
                title: L10n.tr(.interfaceLanguage),
                icon: "globe",
                iconColor: .blue
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr(.interfaceLanguageDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(AppLanguage.allCases) { lang in
                            let isSelected = langManager.currentLanguage == lang

                            Button {
                                langManager.currentLanguage = lang
                                appLanguage = lang
                            } label: {
                                HStack(spacing: 8) {
                                    Text(lang.flag)
                                        .font(.system(size: 16))

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(lang.displayName)
                                            .font(.body.bold())
                                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                    }

                                    if isSelected {
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .font(.system(size: 14))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 1.5 : 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Updates & Version Card
            settingsCard(
                title: L10n.tr(.appUpdates),
                icon: "arrow.triangle.2.circlepath.circle.fill",
                iconColor: .green
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mirza Benevis")
                                .font(.body.bold())
                            Text("\(L10n.tr(.currentVersion)): v\(updateManager.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if updateManager.isChecking {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(L10n.tr(.checkingForUpdates))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if updateManager.isUpdateAvailable {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.green)
                                Text(updateManager.latestVersion.map { "v\($0)" } ?? "")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(L10n.tr(.upToDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if updateManager.isUpdateAvailable {
                        VStack(alignment: .leading, spacing: 8) {
                            if let notes = updateManager.releaseNotes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }

                            Button {
                                updateManager.openDownload()
                            } label: {
                                Label(L10n.tr(.downloadUpdate), systemImage: "arrow.down.doc.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 4)
                    } else {
                        Button {
                            Task {
                                await updateManager.checkForUpdates(isUserInitiated: true)
                            }
                        } label: {
                            Label(L10n.tr(.checkForUpdates), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Model & Whisper

    private var modelTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Whisper Model Selection Card
            settingsCard(
                title: L10n.tr(.whisperSectionTitle),
                icon: "waveform.badge.mic",
                iconColor: .indigo
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker(L10n.tr(.whisperModel), selection: $selectedModel) {
                            ForEach(WhisperModelSize.allCases) { model in
                                HStack {
                                    Text(model.label)
                                    if modelManager.isModelDownloaded(model) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 240)
                        .onChange(of: selectedModel) { _, v in
                            AppSettings.whisperModelSize = v
                        }

                        Spacer()

                        if modelManager.isModelDownloaded(selectedModel) {
                            Label(L10n.tr(.modelDownloaded), systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    // Download Progress or Actions
                    if modelManager.isDownloading {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: modelManager.downloadProgress) {
                                HStack {
                                    Text(modelManager.statusMessage)
                                    Spacer()
                                    if !modelManager.downloadSpeed.isEmpty {
                                        Text(modelManager.downloadSpeed)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            HStack {
                                if modelManager.totalBytes > 0 {
                                    let downStr = ByteCountFormatter.string(fromByteCount: modelManager.downloadedBytes, countStyle: .file)
                                    let totStr = ByteCountFormatter.string(fromByteCount: modelManager.totalBytes, countStyle: .file)
                                    Text("\(downStr) / \(totStr)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(modelManager.downloadProgress * 100))%")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }

                            Button(L10n.tr(.cancelDownload), role: .destructive) {
                                modelManager.cancelDownload()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    } else {
                        if let error = modelManager.downloadError {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(L10n.tr(.downloadFailed), systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Button {
                            Task {
                                try? await modelManager.downloadModel(selectedModel)
                            }
                        } label: {
                            Label(
                                modelManager.isModelDownloaded(selectedModel) ? L10n.tr(.downloadModel) : L10n.tr(.downloadModel),
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Metal GPU Acceleration Card
            settingsCard(
                title: L10n.tr(.metalToggle),
                icon: "bolt.fill",
                iconColor: .orange
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $useGPU) {
                        Text(L10n.tr(.metalToggle))
                            .font(.body)
                    }
                    .onChange(of: useGPU) { _, v in
                        AppSettings.useGPU = v
                    }

                    Text(L10n.tr(.metalDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }

            // Core ML (Optional) Card
            settingsCard(
                title: L10n.tr(.coreMLTitle),
                icon: "cpu",
                iconColor: .purple
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if modelManager.isCoreMLAvailable(for: selectedModel) {
                            Label(L10n.tr(.coreMLActive), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption.bold())
                        } else {
                            Label(L10n.tr(.metalActive), systemImage: "bolt.fill")
                                .foregroundStyle(.blue)
                                .font(.caption.bold())
                        }
                        Spacer()
                    }

                    Text(L10n.tr(.coreMLDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)

                    HStack(spacing: 12) {
                        Button {
                            modelManager.openModelsDirectory()
                        } label: {
                            Label(L10n.tr(.openModelsFolder), systemImage: "folder")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        Spacer()

                        Link(destination: URL(string: "https://github.com/ggerganov/whisper.cpp#core-ml-support")!) {
                            Label(L10n.tr(.coreMLGuide), systemImage: "arrow.up.right.square")
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Tab 3: Gemini AI

    private var geminiTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // API Key Configuration Card
            settingsCard(
                title: L10n.tr(.geminiSectionTitle),
                icon: "sparkles",
                iconColor: .purple
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr(.geminiDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)

                    // Key Input Row
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr(.apiKeyLabel))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            if showKey {
                                TextField(L10n.tr(.apiKeyPlaceholder), text: $geminiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField(L10n.tr(.apiKeyPlaceholder), text: $geminiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)

                            Button(L10n.tr(.saveKey)) {
                                AppSettings.geminiCustomHost = customHost
                                if KeychainHelper.saveGeminiAPIKey(geminiAPIKey) {
                                    withAnimation { savedKey = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        withAnimation { savedKey = false }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                            .disabled(geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if savedKey {
                        Label(L10n.tr(.keySaved), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption.bold())
                            .transition(.opacity)
                    } else if geminiAPIKey.isEmpty {
                        Label(L10n.tr(.keyMissingNotice), systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }

                    // Link to Google AI Studio
                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "key.horizontal")
                            Text(L10n.tr(.getKeyHelp))
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption)
                    }
                    .padding(.top, 2)
                }
            }

            // Model Selection Card
            settingsCard(
                title: langManager.currentLanguage == .english ? "Gemini Model" : "مدل هوش مصنوعی جمینای",
                icon: "brain",
                iconColor: .indigo
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: Binding(
                        get: { AppSettings.geminiModel },
                        set: { AppSettings.geminiModel = $0 }
                    )) {
                        Text("Gemini 2.0 Flash (پیش‌فرض و سریع)").tag("gemini-2.0-flash")
                        Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                        Text("Gemini 1.5 Flash").tag("gemini-1.5-flash")
                        Text("Gemini 1.5 Pro").tag("gemini-1.5-pro")
                    }
                    .pickerStyle(.menu)

                    Text(langManager.currentLanguage == .english ?
                        "Gemini 2.0 Flash is recommended for fast meeting summarization and speaker diarization." :
                        "مدل Gemini 2.0 Flash برای خلاصه‌سازی سریع، استخراج وظایف و تفکیک دقیق گویندگان پیشنهاد می‌شود.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Custom Host & Reverse Proxy Card
            settingsCard(
                title: L10n.tr(.customHostLabel),
                icon: "network",
                iconColor: .teal
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L10n.tr(.customHostPlaceholder), text: $customHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text(L10n.tr(.proxyTip))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - Tab 4: Audio & Voice

    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Default Audio Source Card
            settingsCard(
                title: L10n.tr(.audioSourceSection),
                icon: "speaker.wave.2",
                iconColor: .cyan
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(L10n.tr(.audioSourceSection), selection: Binding(
                        get: { AppSettings.audioSource },
                        set: { AppSettings.audioSource = $0 }
                    )) {
                        ForEach(AudioSourceMode.allCases) { mode in
                            Label(mode.localizedLabel(for: langManager.currentLanguage), systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Text(L10n.tr(.audioSourceDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }

            // Speaker Profile Card
            settingsCard(
                title: L10n.tr(.speakerProfileSection),
                icon: "person.crop.circle",
                iconColor: .blue
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr(.userNameLabel))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    TextField(L10n.tr(.userNamePlaceholder), text: $userName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                        .onChange(of: userName) { _, v in
                            AppSettings.userName = v
                        }

                    Text(L10n.tr(.userNameDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - Tab 5: Calendar

    private var calendarTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: L10n.tr(.calendarSectionTitle),
                icon: "calendar.badge.clock",
                iconColor: .red
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr(.calendarSectionTitle))
                                .font(.body.bold())
                            Text(L10n.tr(.calendarDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }

                        Spacer()

                        if CalendarService.shared.hasCalendarAccess {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(L10n.tr(.calendarAccessGranted))
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                        } else {
                            Button(L10n.tr(.requestCalendarAccess)) {
                                Task {
                                    _ = await CalendarService.shared.requestAccess()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    Text(L10n.tr(.calendarSyncHint))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Reusable Settings Card Container

    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.headline)

                Spacer()
            }

            content()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }
}
