import Foundation

enum AppSettings {
    private static let whisperModelKey = "mirza.whisperModelSize"
    private static let audioSourceKey = "mirza.audioSource"
    private static let useGPUKey = "mirza.useGPU"
    private static let geminiCustomHostKey = "mirza.geminiCustomHost"
    private static let selectedLanguageKey = "mirza.selectedLanguage"
    private static let appLanguageKey = "mirza.appLanguage"
    private static let userNameKey = "mirza.userName"
    private static let geminiModelKey = "mirza.geminiModel"

    static var geminiModel: String {
        get {
            let val = UserDefaults.standard.string(forKey: geminiModelKey) ?? "gemini-2.0-flash"
            return val.isEmpty ? "gemini-2.0-flash" : val
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: geminiModelKey)
        }
    }

    static var appLanguage: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: appLanguageKey) ?? AppLanguage.english.rawValue
            return AppLanguage(rawValue: raw) ?? .english
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: appLanguageKey)
        }
    }

    static var userName: String {
        get {
            let val = UserDefaults.standard.string(forKey: userNameKey) ?? ""
            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "شما" : trimmed
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userNameKey)
        }
    }

    static var selectedLanguage: String? {
        get {
            let val = UserDefaults.standard.string(forKey: selectedLanguageKey) ?? "fa"
            return val == "auto" ? nil : val
        }
        set {
            UserDefaults.standard.set(newValue ?? "auto", forKey: selectedLanguageKey)
        }
    }

    static var geminiCustomHost: String {
        get {
            UserDefaults.standard.string(forKey: geminiCustomHostKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: geminiCustomHostKey)
        }
    }

    static var whisperModelSize: WhisperModelSize {
        get {
            let raw = UserDefaults.standard.string(forKey: whisperModelKey) ?? WhisperModelSize.persianTurbo.rawValue
            if raw == "tiny" || raw == "base" {
                return .persianTurbo
            }
            return WhisperModelSize(rawValue: raw) ?? .persianTurbo
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: whisperModelKey)
        }
    }

    static var audioSource: AudioSourceMode {
        get {
            let raw = UserDefaults.standard.string(forKey: audioSourceKey) ?? AudioSourceMode.systemAudio.rawValue
            return AudioSourceMode(rawValue: raw) ?? .systemAudio
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: audioSourceKey)
        }
    }

    static var useGPU: Bool {
        get {
            if UserDefaults.standard.object(forKey: useGPUKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: useGPUKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: useGPUKey)
        }
    }
}
