import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @EnvironmentObject var transcriptStore: TranscriptStore
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var updateManager: UpdateManager
    @StateObject private var calendarService = CalendarService.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            updateNotice
            calendarNotice
            controls
            Divider()
            liveTranscript
            footer
        }
        .padding(14)
        .frame(width: 380)
        .task {
            await coordinator.prepareModel()
            calendarService.refreshEvents()
            await updateManager.checkForUpdates(isUserInitiated: false)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: coordinator.isActive ? "mic.fill" : "waveform")
                .foregroundStyle(coordinator.isActive ? .red : .primary)
                .symbolEffect(.pulse, isActive: coordinator.isActive)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mirza Benevis")
                    .font(.headline)
                Text(coordinator.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if coordinator.whisperEngine.isProcessing {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var updateNotice: some View {
        if updateManager.isUpdateAvailable {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("نسخه جدید \(updateManager.latestVersion ?? "") موجود است")
                        .font(.caption2)
                        .bold()
                    Text("برای دانلود نسخه جدید کلیک کنید")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("دریافت") {
                    updateManager.openDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var calendarNotice: some View {
        if let event = calendarService.currentEvent {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("رویداد تقویم:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.caption2)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(6)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(6)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("منبع", selection: $coordinator.audioSource) {
                    ForEach(AudioSourceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(coordinator.isActive)
                .onChange(of: coordinator.audioSource) { _, v in AppSettings.audioSource = v }

                Picker("زبان", selection: $coordinator.selectedLanguage) {
                    Text("فارسی").tag("fa" as String?)
                    Text("English").tag("en" as String?)
                    Text("خودکار").tag(nil as String?)
                }
                .pickerStyle(.menu)
                .frame(minWidth: 85)
                .disabled(coordinator.isActive)
                .onChange(of: coordinator.selectedLanguage) { _, v in
                    AppSettings.selectedLanguage = v
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        if coordinator.isActive {
                            await coordinator.stopRecording()
                        } else {
                            await coordinator.startRecording()
                        }
                    }
                } label: {
                    Label(
                        coordinator.isActive ? "توقف" : "شروع ضبط",
                        systemImage: coordinator.isActive ? "stop.circle.fill" : "record.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(coordinator.isActive ? .red : .accentColor)
                .disabled(!coordinator.whisperEngine.isModelLoaded && !coordinator.isActive)

                Button {
                    coordinator.copyCurrentTranscript()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("کپی در کلیپ‌بورد")
                .disabled(transcriptStore.currentSession?.fullText.isEmpty ?? true)
            }

            if !coordinator.whisperEngine.isModelLoaded, let err = coordinator.whisperEngine.loadError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if modelManager.isDownloading {
                ProgressView(value: modelManager.downloadProgress) {
                    Text("دانلود مدل...")
                        .font(.caption2)
                }
            }
        }
    }

    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("رونوشت زنده")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if let mode = AppSettings.audioSource == .both ? "تفکیک گوینده فعال" : nil {
                    Text(mode)
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                }
            }

            ScrollView {
                if let session = transcriptStore.currentSession, !session.segments.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(session.segments.suffix(10)) { segment in
                            HStack(alignment: .top, spacing: 6) {
                                Text(segment.speakerDisplayName)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(speakerColor(segment.speakerDisplayName).opacity(0.18))
                                    .foregroundStyle(speakerColor(segment.speakerDisplayName))
                                    .cornerRadius(4)

                                Text(segment.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else if let words = transcriptStore.currentSession?.words, !words.isEmpty {
                    Text(words.map(\.text).joined(separator: " "))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("متن گفتگو در این قسمت ظاهر می‌شود...")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .frame(height: 130)
        }
    }

    private func speakerColor(_ name: String) -> Color {
        if name == "شما" || name == AppSettings.userName {
            return .blue
        }
        let palette: [Color] = [.purple, .teal, .orange, .pink, .indigo, .green, .mint, .cyan]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Button("جلسات") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "sessions")
                }
                Button("تنظیمات") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                Spacer()
                Text("\(transcriptStore.currentSession?.wordCount ?? 0) کلمه")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button {
                    Task {
                        if coordinator.isActive {
                            await coordinator.stopRecording()
                        }
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Label("خروج از برنامه", systemImage: "power")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                Spacer()
            }
        }
    }
}

struct SessionsWindowView: View {
    @EnvironmentObject var transcriptStore: TranscriptStore

    var body: some View {
        SessionsListView()
            .frame(minWidth: 880, minHeight: 560)
    }
}

struct SettingsWindowView: View {
    var body: some View {
        SettingsView()
    }
}
