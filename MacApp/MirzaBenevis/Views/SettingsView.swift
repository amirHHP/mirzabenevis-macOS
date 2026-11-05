import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var updateManager: UpdateManager
    @Environment(\.dismiss) private var dismiss

    @State private var geminiAPIKey = KeychainHelper.loadGeminiAPIKey() ?? ""
    @State private var customHost = AppSettings.geminiCustomHost
    @State private var showKey = false
    @State private var saved = false
    @State private var selectedModel = AppSettings.whisperModelSize
    @State private var useGPU = AppSettings.useGPU
    @State private var userName = AppSettings.userName

    var body: some View {
        Form {
            Section("مدل whisper.cpp (on-device)") {
                Picker("مدل", selection: $selectedModel) {
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
                .onChange(of: selectedModel) { _, v in AppSettings.whisperModelSize = v }

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
                                let downloadedStr = ByteCountFormatter.string(fromByteCount: modelManager.downloadedBytes, countStyle: .file)
                                let totalStr = ByteCountFormatter.string(fromByteCount: modelManager.totalBytes, countStyle: .file)
                                Text("\(downloadedStr) از \(totalStr)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if modelManager.downloadProgress > 0 {
                                Text("\(Int(modelManager.downloadProgress * 100))%")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("لغو دانلود", role: .destructive) {
                        modelManager.cancelDownload()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                } else {
                    if let error = modelManager.downloadError {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("خطا در دانلود", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    Button("دانلود / به‌روزرسانی مدل") {
                        Task {
                            try? await modelManager.downloadModel(selectedModel)
                        }
                    }
                    .disabled(modelManager.isDownloading)
                }

                Toggle("Metal / GPU (Apple Silicon)", isOn: $useGPU)
                    .onChange(of: useGPU) { _, v in AppSettings.useGPU = v }

                Text("مدل روی Neural Engine و Metal اجرا می‌شود — بدون سرور Python، بدون فشار به باتری.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("کلید API جمینای (خلاصه‌سازی)") {
                HStack {
                    if showKey {
                        TextField("AIza...", text: $geminiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("AIza...", text: $geminiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Button("ذخیره") {
                    AppSettings.geminiCustomHost = customHost
                    if KeychainHelper.saveGeminiAPIKey(geminiAPIKey) { saved = true }
                }
                .disabled(geminiAPIKey.isEmpty)

                if saved {
                    Label("ذخیره شد", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("آدرس هاست / پروکسی معکوس (اختیاری):")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("https://generativelanguage.googleapis.com", text: $customHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Text("نکته: در صورت استفاده از داخل ایران، VPN را فعال کنید یا از آدرس پروکسی معتبر استفاده کنید.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("منبع صدا") {
                Picker("پیش‌فرض", selection: Binding(
                    get: { AppSettings.audioSource },
                    set: { AppSettings.audioSource = $0 }
                )) {
                    ForEach(AudioSourceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }

                Text("در حالت «میک + سیستم»، برنامه با مقایسه انرژی صداها گویندگان را به صورت «شما» و «جلسه» تفکیک می‌کند.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("مشخصات گوینده پیش‌فرض") {
                HStack {
                    Text("نام شما (میکروفون):")
                        .font(.body)
                    TextField("مثلاً: علی یا شما", text: $userName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: userName) { _, v in
                            AppSettings.userName = v
                        }
                }

                Text("این نام هنگام ضبط مکالمه با میکروفون، به عنوان برچسب گوینده به جای «شما» استفاده می‌شود.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("یکپارچگی با تقویم مک (Calendar Integration)") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("اتصال به تقویم و رویدادهای جلسات")
                            .font(.body)
                        Text("نام جلسه و موضوع به‌طور خودکار هنگام شروع ضبط از تقویم برداشته می‌شود.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if CalendarService.shared.hasCalendarAccess {
                        Label("فعال", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("درخواست دسترسی") {
                            Task {
                                _ = await CalendarService.shared.requestAccess()
                            }
                        }
                    }
                }
            }

            Section("Core ML (اختیاری)") {
                Text("برای سرعت بیشتر encoder، مدل Core ML را از README پروژه whisper.cpp بسازید و در پوشه models قرار دهید.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("به‌روزرسانی برنامه (Updates)") {
                HStack {
                    Text("نسخه فعلی برنامه:")
                    Spacer()
                    Text("v\(updateManager.currentVersion)")
                        .foregroundStyle(.secondary)
                }

                if updateManager.isChecking {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("در حال بررسی نسخه جدید در گیت‌هاب...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if updateManager.isUpdateAvailable {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                            Text("نسخه جدید \(updateManager.latestVersion ?? "") موجود است!")
                                .font(.headline)
                        }

                        if let notes = updateManager.releaseNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }

                        Button {
                            updateManager.openDownload()
                        } label: {
                            Label("دانلود نسخه جدید (DMG)", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack {
                        Button("بررسی نسخه جدید") {
                            Task {
                                await updateManager.checkForUpdates(isUserInitiated: true)
                            }
                        }
                        Spacer()
                        if let msg = updateManager.checkStatusMessage {
                            Text(msg)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("تنظیمات")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("بستن") { dismiss() }
            }
        }
    }
}
