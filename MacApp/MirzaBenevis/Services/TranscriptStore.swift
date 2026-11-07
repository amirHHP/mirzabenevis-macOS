import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var currentSession: TranscriptionSession?
    @Published private(set) var sessions: [TranscriptionSession] = []
    @Published var isRecording = false

    private let storageURL: URL
    private let sessionsDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("MirzaBenevis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("sessions.json")
        sessionsDirectory = dir.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        loadSessions()
    }

    private func sessionFileURL(for id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
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

    func appendSegment(_ segment: TranscriptSegment, targetSessionID: UUID? = nil) {
        // If targetSessionID is specified and currentSession is different, route to the target session
        if let targetID = targetSessionID, currentSession?.id != targetID {
            if let index = sessions.firstIndex(where: { $0.id == targetID }) {
                sessions[index].segments.append(segment)
                sessions[index].words.append(contentsOf: segment.words)
                sessions[index].updatedAt = Date()
                saveSessions()
            }
            return
        }

        guard var session = currentSession else { return }
        session.segments.append(segment)
        session.words.append(contentsOf: segment.words)
        session.updatedAt = Date()
        currentSession = session

        // If recording has already stopped, ensure changes persist to the session list
        if !isRecording {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            }
            saveSessions()
        }
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

    func addActionItem(_ item: MeetingActionItem, to sessionID: UUID) {
        if let current = currentSession, current.id == sessionID {
            var updated = current
            updated.actionItems.append(item)
            currentSession = updated
        }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].actionItems.append(item)
            sessions[index].updatedAt = Date()
        }
        saveSessions()
    }

    func deleteActionItem(_ itemID: UUID, from sessionID: UUID) {
        if let current = currentSession, current.id == sessionID {
            var updated = current
            updated.actionItems.removeAll { $0.id == itemID }
            currentSession = updated
        }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].actionItems.removeAll { $0.id == itemID }
            sessions[index].updatedAt = Date()
        }
        saveSessions()
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

    // MARK: - Speaker & Attendee Management

    func updateSegmentSpeaker(segmentID: UUID, speakerName: String, in sessionID: UUID) {
        let trimmed = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let updateSession: (inout TranscriptionSession) -> Void = { session in
            if let idx = session.segments.firstIndex(where: { $0.id == segmentID }) {
                session.segments[idx].speakerCustomName = trimmed
                if !session.attendees.contains(trimmed) && trimmed != "شما" && trimmed != "جلسه" {
                    session.attendees.append(trimmed)
                }
                session.updatedAt = Date()
            }
        }

        if currentSession?.id == sessionID {
            var updated = currentSession!
            updateSession(&updated)
            currentSession = updated
        }

        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            updateSession(&sessions[index])
            saveSessions()
        }
    }

    func renameSpeakerGlobally(from oldName: String, to newName: String, in sessionID: UUID) {
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty else { return }

        let updateSession: (inout TranscriptionSession) -> Void = { session in
            var modified = false
            for i in session.segments.indices {
                if session.segments[i].speakerDisplayName == oldName {
                    session.segments[i].speakerCustomName = trimmedNew
                    modified = true
                }
            }
            if let attIdx = session.attendees.firstIndex(of: oldName) {
                session.attendees[attIdx] = trimmedNew
            } else if !session.attendees.contains(trimmedNew) && trimmedNew != "شما" && trimmedNew != "جلسه" {
                session.attendees.append(trimmedNew)
            }
            if modified {
                session.updatedAt = Date()
            }
        }

        if currentSession?.id == sessionID {
            var updated = currentSession!
            updateSession(&updated)
            currentSession = updated
        }

        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            updateSession(&sessions[index])
            saveSessions()
        }
    }

    func addAttendee(_ name: String, to sessionID: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let updateSession: (inout TranscriptionSession) -> Void = { session in
            if !session.attendees.contains(trimmed) {
                session.attendees.append(trimmed)
                session.updatedAt = Date()
            }
        }

        if currentSession?.id == sessionID {
            var updated = currentSession!
            updateSession(&updated)
            currentSession = updated
        }

        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            updateSession(&sessions[index])
            saveSessions()
        }
    }

    func removeAttendee(_ name: String, from sessionID: UUID) {
        let updateSession: (inout TranscriptionSession) -> Void = { session in
            session.attendees.removeAll { $0 == name }
            session.updatedAt = Date()
        }

        if currentSession?.id == sessionID {
            var updated = currentSession!
            updateSession(&updated)
            currentSession = updated
        }

        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            updateSession(&sessions[index])
            saveSessions()
        }
    }

    func applyDiarization(assignments: [UUID: String], to sessionID: UUID) {
        guard !assignments.isEmpty else { return }

        let updateSession: (inout TranscriptionSession) -> Void = { session in
            for i in session.segments.indices {
                if let name = assignments[session.segments[i].id] {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        session.segments[i].speakerCustomName = trimmed
                        if !session.attendees.contains(trimmed) && trimmed != "شما" && trimmed != "جلسه" {
                            session.attendees.append(trimmed)
                        }
                    }
                }
            }
            session.updatedAt = Date()
        }

        if currentSession?.id == sessionID {
            var updated = currentSession!
            updateSession(&updated)
            currentSession = updated
        }

        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            updateSession(&sessions[index])
            saveSessions()
        }
    }

    func deleteSession(_ session: TranscriptionSession) {
        // 1. Delete associated audio recording file if it exists to prevent disk leaks
        if let audioPath = session.audioFilePath, !audioPath.isEmpty {
            if FileManager.default.fileExists(atPath: audioPath) {
                do {
                    try FileManager.default.removeItem(atPath: audioPath)
                    print("[TranscriptStore] ✅ Deleted audio recording file: \(audioPath)")
                } catch {
                    print("[TranscriptStore] ⚠️ Failed to delete audio file at \(audioPath): \(error)")
                }
            }
        }

        // 2. Delete the individual session file
        let fileURL = sessionFileURL(for: session.id)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
            print("[TranscriptStore] ✅ Deleted session file: \(fileURL.lastPathComponent)")
        }

        // 3. Update memory state
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = nil
        }
    }

    func loadSession(_ session: TranscriptionSession) {
        currentSession = session
    }

    private func loadSessions() {
        // 1. Check for legacy sessions.json and migrate to per-session files
        if FileManager.default.fileExists(atPath: storageURL.path) {
            do {
                let data = try Data(contentsOf: storageURL)
                let legacySessions = try JSONDecoder().decode([TranscriptionSession].self, from: data)
                print("[TranscriptStore] Migrating \(legacySessions.count) legacy sessions to per-session files...")
                for s in legacySessions {
                    saveSessionFile(s)
                }
                let backupURL = storageURL.deletingPathExtension().appendingPathExtension("json.migrated")
                try? FileManager.default.moveItem(at: storageURL, to: backupURL)
                print("[TranscriptStore] ✅ Legacy sessions.json migrated successfully")
            } catch {
                print("[TranscriptStore] Failed to migrate legacy sessions: \(error)")
            }
        }

        // 2. Load all sessions from the sessions directory
        guard let files = try? FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        var loaded: [TranscriptionSession] = []
        let jsonDecoder = JSONDecoder()

        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let session = try? jsonDecoder.decode(TranscriptionSession.self, from: data) else {
                continue
            }
            loaded.append(session)
        }

        sessions = loaded.sorted { $0.createdAt > $1.createdAt }
        print("[TranscriptStore] ✅ Loaded \(sessions.count) sessions from per-session storage")
    }

    func saveSessionFile(_ session: TranscriptionSession) {
        let fileURL = sessionFileURL(for: session.id)
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[TranscriptStore] ❌ Failed to save session \(session.id): \(error)")
        }
    }

    private func saveSessions() {
        if let current = currentSession {
            if let index = sessions.firstIndex(where: { $0.id == current.id }) {
                sessions[index] = current
            } else {
                sessions.insert(current, at: 0)
            }
            saveSessionFile(current)
        }
    }
}
