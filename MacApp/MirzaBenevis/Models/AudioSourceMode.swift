import Foundation

enum AudioSourceMode: String, CaseIterable, Identifiable, Codable {
    case microphone
    case systemAudio
    case both

    var id: String { rawValue }

    var label: String {
        localizedLabel(for: LanguageManager.shared.currentLanguage)
    }

    func localizedLabel(for lang: AppLanguage = LanguageManager.shared.currentLanguage) -> String {
        switch lang {
        case .english:
            switch self {
            case .microphone: return "Microphone"
            case .systemAudio: return "System Audio"
            case .both: return "Both (Mic + System)"
            }
        case .persian:
            switch self {
            case .microphone: return "میکروفون"
            case .systemAudio: return "صدای سیستم"
            case .both: return "هر دو (میک + سیستم)"
            }
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .systemAudio: return "speaker.wave.2.fill"
        case .both: return "mic.and.signal.meter.fill"
        }
    }
}
