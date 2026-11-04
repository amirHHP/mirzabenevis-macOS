import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var currentSession: TranscriptionSession?
    @Published private(set) var sessions: [TranscriptionSession] = []
    @Published var isRecording = false

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("MirzaBenevis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("sessions.json")
        loadSessions()
    }

    func startNewSession(language: String? = nil, title: String? = nil, calendarEventTitle: String? = nil) {
        let defaultTitle = title ?? calendarEventTitle ?? "جلسه جدید"
        let session = TranscriptionSession(
            title: defaultTitle,
            language: language,
            calendarEventTitle: calendarEventTitle
        )
        currentSession = session
        isRecording = true
    }

    func appendSegment(_ segment: TranscriptSegment) {
        guard var session = currentSession else { return }
        session.segments.append(segment)
        session.words.append(contentsOf: segment.words)
        session.updatedAt = Date()
        currentSession = session
    }

    func appendWords(_ words: [TranscriptWord]) {
        guard var session = currentSession, !words.isEmpty else { return }
        session.words.append(contentsOf: words)
        session.updatedAt = Date()
        currentSession = session
    }

    func stopSession(audioFilePath: String? = nil) {
        guard var session = currentSession else { return }
        session.updatedAt = Date()
        if let path = audioFilePath {
            session.audioFilePath = path
        }
        if sessions.contains(where: { $0.id == session.id }) {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            }
        } else {
            sessions.insert(session, at: 0)
        }
        currentSession = session
        saveSessions()
        isRecording = false
    }

    func setSummary(_ summary: String, for sessionID: UUID) {
        if currentSession?.id == sessionID {
            currentSession?.summary = summary
        }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].summary = summary
            sessions[index].updatedAt = Date()
        }
        saveSessions()
    }

    func setActionItems(_ items: [MeetingActionItem], for sessionID: UUID) {
        if currentSession?.id == sessionID {
            currentSession?.actionItems = items
        }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].actionItems = items
            sessions[index].updatedAt = Date()
        }
        saveSessions()
    }

    func toggleActionItem(_ itemID: UUID, in sessionID: UUID) {
        if let current = currentSession, current.id == sessionID {
            if let itemIndex = current.actionItems.firstIndex(where: { $0.id == itemID }) {
                var updated = current
                updated.actionItems[itemIndex].isCompleted.toggle()
                currentSession = updated
            }
        }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            if let itemIndex = sessions[index].actionItems.firstIndex(where: { $0.id == itemID }) {
                sessions[index].actionItems[itemIndex].isCompleted.toggle()
                sessions[index].updatedAt = Date()
                saveSessions()
            }
        }
    }

    func updateTitle(_ title: String, for sessionID: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if currentSession?.id == sessionID {
            currentSession?.title = trimmed
        }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].title = trimmed
            sessions[index].updatedAt = Date()
            saveSessions()
        }
    }

    func deleteSession(_ session: TranscriptionSession) {
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = nil
        }
        saveSessions()
    }

    func loadSession(_ session: TranscriptionSession) {
        currentSession = session
    }

    private func loadSessions() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            sessions = try JSONDecoder().decode([TranscriptionSession].self, from: data)
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }

    private func saveSessions() {
        var all = sessions
        if let current = currentSession,
           !all.contains(where: { $0.id == current.id }) {
            all.insert(current, at: 0)
        } else if let current = currentSession,
                  let index = all.firstIndex(where: { $0.id == current.id }) {
            all[index] = current
        }
        do {
            let data = try JSONEncoder().encode(all)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }
}
