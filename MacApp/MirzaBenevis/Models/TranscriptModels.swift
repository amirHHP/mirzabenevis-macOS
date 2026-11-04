import Foundation

enum SpeakerType: String, Codable, Hashable, CaseIterable {
    case user      // میکروفون (کاربر)
    case system    // صدای سیستم (سایر شرکت‌کنندگان جلسه)
    case unknown   // منبع ترکیبی یا نامشخص

    var displayName: String {
        switch self {
        case .user: return "شما"
        case .system: return "جلسه / طرف مقابل"
        case .unknown: return "گوینده"
        }
    }

    var shortLabel: String {
        switch self {
        case .user: return "شما"
        case .system: return "جلسه"
        case .unknown: return "صدا"
        }
    }

    var icon: String {
        switch self {
        case .user: return "person.fill"
        case .system: return "person.2.fill"
        case .unknown: return "waveform"
        }
    }
}

struct TranscriptWord: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
    let receivedAt: Date
    let speaker: SpeakerType

    init(
        id: UUID = UUID(),
        text: String,
        start: Double,
        end: Double,
        confidence: Double = 0,
        receivedAt: Date = Date(),
        speaker: SpeakerType = .unknown
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
        self.receivedAt = receivedAt
        self.speaker = speaker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt) ?? Date()
        speaker = try container.decodeIfPresent(SpeakerType.self, forKey: .speaker) ?? .unknown
    }
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var speaker: SpeakerType
    var speakerCustomName: String?
    var text: String
    var start: Double
    var end: Double
    var words: [TranscriptWord]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        speaker: SpeakerType = .unknown,
        speakerCustomName: String? = nil,
        text: String,
        start: Double,
        end: Double,
        words: [TranscriptWord] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.speaker = speaker
        self.speakerCustomName = speakerCustomName
        self.text = text
        self.start = start
        self.end = end
        self.words = words
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        speaker = try container.decodeIfPresent(SpeakerType.self, forKey: .speaker) ?? .unknown
        speakerCustomName = try container.decodeIfPresent(String.self, forKey: .speakerCustomName)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        start = try container.decodeIfPresent(Double.self, forKey: .start) ?? 0
        end = try container.decodeIfPresent(Double.self, forKey: .end) ?? 0
        words = try container.decodeIfPresent([TranscriptWord].self, forKey: .words) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var speakerDisplayName: String {
        if let custom = speakerCustomName, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        if speaker == .user {
            return AppSettings.userName
        }
        return speaker.displayName
    }

    var formattedTime: String {
        let totalSeconds = Int(start)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct MeetingActionItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var isCompleted: Bool
    var assignee: String?

    init(
        id: UUID = UUID(),
        text: String,
        isCompleted: Bool = false,
        assignee: String? = nil
    ) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.assignee = assignee
    }
}

struct TranscriptionSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var words: [TranscriptWord]
    var segments: [TranscriptSegment]
    var actionItems: [MeetingActionItem]
    var attendees: [String]
    var summary: String?
    var createdAt: Date
    var updatedAt: Date
    var language: String?
    var audioFilePath: String?
    var calendarEventTitle: String?

    init(
        id: UUID = UUID(),
        title: String = "جلسه جدید",
        words: [TranscriptWord] = [],
        segments: [TranscriptSegment] = [],
        actionItems: [MeetingActionItem] = [],
        attendees: [String] = [],
        summary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        language: String? = nil,
        audioFilePath: String? = nil,
        calendarEventTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.words = words
        self.segments = segments
        self.actionItems = actionItems
        self.attendees = attendees
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.language = language
        self.audioFilePath = audioFilePath
        self.calendarEventTitle = calendarEventTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "جلسه جدید"
        words = try container.decodeIfPresent([TranscriptWord].self, forKey: .words) ?? []
        segments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        actionItems = try container.decodeIfPresent([MeetingActionItem].self, forKey: .actionItems) ?? []
        attendees = try container.decodeIfPresent([String].self, forKey: .attendees) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        language = try container.decodeIfPresent(String.self, forKey: .language)
        audioFilePath = try container.decodeIfPresent(String.self, forKey: .audioFilePath)
        calendarEventTitle = try container.decodeIfPresent(String.self, forKey: .calendarEventTitle)

        // If legacy session had no segments, construct one from words or empty
        if segments.isEmpty && !words.isEmpty {
            let full = words.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !full.isEmpty {
                let firstStart = words.first?.start ?? 0
                let lastEnd = words.last?.end ?? 0
                let spk = words.first?.speaker ?? .unknown
                segments = [
                    TranscriptSegment(
                        speaker: spk,
                        text: full,
                        start: firstStart,
                        end: lastEnd,
                        words: words,
                        createdAt: createdAt
                    )
                ]
            }
        }
    }

    var fullText: String {
        if !segments.isEmpty {
            return segments.map(\.text).joined(separator: " ")
        }
        return words.map(\.text).joined(separator: " ")
    }

    var formattedDialogue: String {
        if segments.isEmpty {
            return fullText
        }
        return segments.map { seg in
            "[\(seg.speakerDisplayName)] (\(seg.formattedTime)): \(seg.text)"
        }.joined(separator: "\n\n")
    }

    var distinctSpeakers: [String] {
        var names = Set<String>()
        for seg in segments {
            let name = seg.speakerDisplayName
            if !name.isEmpty {
                names.insert(name)
            }
        }
        for att in attendees {
            let trimmed = att.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                names.insert(trimmed)
            }
        }
        if names.isEmpty {
            return [AppSettings.userName, "جلسه"]
        }
        return Array(names).sorted()
    }

    var wordCount: Int {
        if !words.isEmpty { return words.count }
        return fullText.split(whereSeparator: \.isWhitespace).count
    }

    var audioFileURL: URL? {
        guard let path = audioFilePath else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
