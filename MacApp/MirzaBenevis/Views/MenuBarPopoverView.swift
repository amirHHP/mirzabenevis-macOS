import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @EnvironmentObject var transcriptStore: TranscriptStore
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var updateManager: UpdateManager
    @ObservedObject private var langManager = LanguageManager.shared
    @StateObject private var calendarService = CalendarService.shared
    @Environment(\.openWindow) private var openWindow

    @State private var copyToast = false

    var body: some View {
        VStack(spacing: 12) {
            header
            if updateManager.isUpdateAvailable {
                updateNotice
            }
            if calendarService.currentEvent != nil {
                calendarNotice
            }
            if coordinator.permissionError != nil {
                permissionNotice
            }
            recordingCard
            liveTranscriptCard
            footer
        }
        .padding(14)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.layoutDirection, langManager.layoutDirection)
        .task {
            await coordinator.prepareModel()
            calendarService.refreshEvents()
            await updateManager.checkForUpdates(isUserInitiated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.reopenNotification)) { _ in
            openWindow(id: "sessions")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            // App Icon & Pulsing State
            ZStack {
                Circle()
                    .fill(coordinator.isActive ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: coordinator.isActive ? "mic.fill" : "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(coordinator.isActive ? Color.red : Color.accentColor)
                    .symbolEffect(.pulse, isActive: coordinator.isActive)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr(.appTitle))
                    .font(.headline)

                HStack(spacing: 5) {
                    Circle()
                        .fill(headerStatusColor)
                        .frame(width: 6, height: 6)

                    Text(headerStatusText)
                        .font(.caption2)
                        .foregroundStyle(coordinator.permissionError != nil ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if coordinator.whisperEngine.isProcessing {
                ProgressView().controlSize(.small)
            }

            // Language Switcher Pill
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
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                    Text(langManager.currentLanguage.shortLabel)
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .help(L10n.tr(.language))

            // Settings Icon Button
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.tr(.settings))
        }
    }

    // MARK: - Update Notice Banner

    @ViewBuilder
    private var updateNotice: some View {
        if updateManager.isUpdateAvailable {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.tr(.updateAvailable(updateManager.latestVersion ?? "")))
                        .font(.caption.bold())
                    Text(L10n.tr(.clickToDownload))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.tr(.download)) {
                    updateManager.openDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(9)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Calendar Notice Banner

    @ViewBuilder
    private var calendarNotice: some View {
        if let event = calendarService.currentEvent {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr(.calendarEvent))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.caption2.bold())
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Permission Notice Banner

    @ViewBuilder
    private var permissionNotice: some View {
        if let err = coordinator.permissionError {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(permissionTitle(for: err))
                            .font(.caption.bold())
                            .foregroundStyle(.primary)

                        Text(permissionDescription(for: err))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Button {
                        coordinator.dismissPermissionError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(langManager.isRTL ? "بستن پیام" : "Dismiss")
                }

                HStack(spacing: 8) {
                    Button {
                        openPermissionSettings(for: err)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 9))
                            Text(langManager.isRTL ? "باز کردن تنظیمات مک" : "Open System Settings")
                                .font(.caption2.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)

                    if err == .systemAudio || err == .both {
                        Text(langManager.isRTL ? "💡 نکته: دسترسی را با (-) حذف و دوباره (+) اضافه کنید." : "💡 Tip: Remove (-) & re-add (+).")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
            }
            .padding(10)
            .background(Color.orange.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    private var headerStatusColor: Color {
        if coordinator.isActive { return Color.red }
        if coordinator.permissionError != nil { return Color.orange }
        return coordinator.whisperEngine.isModelLoaded ? Color.green : Color.orange
    }

    private var headerStatusText: String {
        if coordinator.isActive { return L10n.tr(.recording) }
        if coordinator.permissionError != nil {
            return langManager.isRTL ? "نیازمند تنظیم دسترسی" : "Permission Required"
        }
        return coordinator.whisperEngine.isModelLoaded ? L10n.tr(.ready) : coordinator.statusMessage
    }

    private func permissionTitle(for err: PermissionErrorType) -> String {
        switch err {
        case .microphone:
            return langManager.isRTL ? "دسترسی میکروفون رد شد" : "Microphone Access Denied"
        case .systemAudio:
            return langManager.isRTL ? "دسترسی ضبط صدای سیستم تأیید نشد" : "System Audio Permission Required"
        case .both:
            return langManager.isRTL ? "نیاز به مجوز میکروفون و صدای سیستم" : "Audio Permissions Required"
        }
    }

    private func permissionDescription(for err: PermissionErrorType) -> String {
        switch err {
        case .microphone:
            return langManager.isRTL
                ? "برای ضبط صدای شما، لطفاً دسترسی به میکروفون را در تنظیمات مک فعال کنید."
                : "Please grant Microphone access for Mirza Benevis in macOS System Settings."
        case .systemAudio:
            return langManager.isRTL
                ? "مک برای ضبط صدای سیستم به دسترسی Screen & System Audio Recording نیاز دارد. اگر تیک روشن است اما کار نمی‌کند، دسترسی برنامه را با دکمه (-) حذف و دوباره (+) اضافه کنید، سپس برنامه را ببندید و باز کنید."
                : "macOS requires Screen & System Audio Recording access. If already enabled, remove (-) and re-add (+) MirzaBenevis, then quit and reopen the app."
        case .both:
            return langManager.isRTL
                ? "برای ضبط هم‌زمان، به دسترسی میکروفون و ضبط صدای سیستم نیاز است. در صورت نیاز دسترسی را با (-) حذف و دوباره اضافه کنید."
                : "Both Microphone and Screen Recording are required. If already enabled, remove (-) and re-add (+) in Settings."
        }
    }

    private func openPermissionSettings(for err: PermissionErrorType) {
        let path: String
        switch err {
        case .microphone:
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .systemAudio, .both:
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let url = URL(string: path) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Hero Recording Card

    private var recordingCard: some View {
        VStack(spacing: 10) {
            // Source & Speech Language Selectors
            HStack(spacing: 8) {
                // Audio Source Picker
                Menu {
                    ForEach(AudioSourceMode.allCases) { mode in
                        Button {
                            coordinator.audioSource = mode
                            AppSettings.audioSource = mode
                        } label: {
                            Label(mode.localizedLabel(for: langManager.currentLanguage), systemImage: mode.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: coordinator.audioSource.icon)
                            .font(.system(size: 11))
                        Text(coordinator.audioSource.localizedLabel(for: langManager.currentLanguage))
                            .font(.caption)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .menuStyle(.borderlessButton)
                .disabled(coordinator.isActive)

                // Speech Language Picker
                Menu {
                    Button {
                        coordinator.selectedLanguage = nil
                        AppSettings.selectedLanguage = nil
                    } label: {
                        HStack {
                            Text(L10n.tr(.autoLanguage))
                            if coordinator.selectedLanguage == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        coordinator.selectedLanguage = "fa"
                        AppSettings.selectedLanguage = "fa"
                    } label: {
                        HStack {
                            Text("فارسی")
                            if coordinator.selectedLanguage == "fa" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        coordinator.selectedLanguage = "en"
                        AppSettings.selectedLanguage = "en"
                    } label: {
                        HStack {
                            Text("English")
                            if coordinator.selectedLanguage == "en" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 10))
                        Text(speechLanguageLabel)
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .menuStyle(.borderlessButton)
                .disabled(coordinator.isActive)

                Spacer()
            }

            // Big Action Button (Start / Stop Recording)
            Button {
                Task {
                    if coordinator.isActive {
                        await coordinator.stopRecording()
                    } else {
                        await coordinator.startRecording()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: coordinator.isActive ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 16, weight: .bold))

                    Text(coordinator.isActive ? L10n.tr(.stopRecording) : L10n.tr(.startRecording))
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .tint(coordinator.isActive ? Color.red : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(!coordinator.whisperEngine.isModelLoaded && !coordinator.isActive)

            // Model Loading / Error Status
            if !coordinator.whisperEngine.isModelLoaded, let err = coordinator.whisperEngine.loadError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if modelManager.isDownloading {
                ProgressView(value: modelManager.downloadProgress) {
                    Text(L10n.tr(.downloadingModel))
                        .font(.caption2)
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(coordinator.isActive ? Color.red.opacity(0.04) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(coordinator.isActive ? Color.red.opacity(0.2) : Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var speechLanguageLabel: String {
        switch coordinator.selectedLanguage {
        case "fa": return "فارسی"
        case "en": return "English"
        default: return L10n.tr(.autoLanguage)
        }
    }

    // MARK: - Live Transcript Card

    private var liveTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr(.liveTranscript))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if copyToast {
                    Text(L10n.tr(.copiedToClipboard))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                if AppSettings.audioSource == .both {
                    Text(L10n.tr(.speakerDiarizationActive))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }

                Button {
                    coordinator.copyCurrentTranscript()
                    withAnimation { copyToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { copyToast = false }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.tr(.copyTranscript))
                .disabled(transcriptStore.currentSession?.fullText.isEmpty ?? true)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if let session = transcriptStore.currentSession, !session.segments.isEmpty {
                            ForEach(session.segments.suffix(10)) { segment in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(segment.speakerDisplayName)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(speakerColor(segment.speakerDisplayName).opacity(0.15))
                                        .foregroundStyle(speakerColor(segment.speakerDisplayName))
                                        .clipShape(Capsule())

                                    Text(segment.text)
                                        .font(.callout)
                                        .lineSpacing(2)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(segment.id)
                            }
                        } else if let words = transcriptStore.currentSession?.words, !words.isEmpty {
                            Text(words.map(\.text).joined(separator: " "))
                                .font(.callout)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "waveform.badge.mic")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.tertiary)
                                Text(L10n.tr(.readyToRecord))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 90)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 125)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                )
                .onChange(of: transcriptStore.currentSession?.segments.count) { _, _ in
                    if let last = transcriptStore.currentSession?.segments.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func speakerColor(_ name: String) -> Color {
        if name == "شما" || name == "You" || name == AppSettings.userName {
            return .blue
        }
        if name == "جلسه" || name == "جلسه / طرف مقابل" || name == "Meeting / Others" {
            return .orange
        }
        let palette: [Color] = [.purple, .teal, .pink, .indigo, .green, .mint, .cyan]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // Open Meetings Window
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "sessions")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                    Text(L10n.tr(.openSessions))
                        .font(.caption.bold())
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let count = transcriptStore.currentSession?.wordCount, count > 0 {
                Text("\(count) \(L10n.tr(.words))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Quit App Button
            Button {
                Task {
                    if coordinator.isActive {
                        await coordinator.stopRecording()
                    }
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10))
                    Text(L10n.tr(.quitApp))
                        .font(.caption)
                }
                .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(L10n.tr(.quitApp))
        }
        .padding(.top, 2)
    }
}

// MARK: - Window Container Wrappers

struct SessionsWindowView: View {
    @EnvironmentObject var transcriptStore: TranscriptStore

    var body: some View {
        SessionsListView()
            .frame(minWidth: 920, minHeight: 600)
    }
}

struct SettingsWindowView: View {
    var body: some View {
        SettingsView()
    }
}
