import SwiftUI
import AppKit

enum SpeakerColorHelper {
    static func color(for name: String) -> Color {
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
}

struct SessionTranscriptTabView: View {
    let session: TranscriptionSession
    let geminiAPIKey: String
    @ObservedObject var audioPlayer: AudioPlayerService
    @Binding var activeEditingSegment: TranscriptSegment?

    @EnvironmentObject var transcriptStore: TranscriptStore

    @State private var transcriptFilter = ""
    @State private var newAttendeeName = ""
    @State private var isDiarizing = false
    @State private var diarizeError: String?
    @State private var diarizeSuccess: String?

    private var filteredSegments: [TranscriptSegment] {
        let q = transcriptFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return session.segments
        }
        return session.segments.filter {
            $0.text.localizedCaseInsensitiveContains(q) ||
            $0.speakerDisplayName.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Attendees & Diarization Bar
            attendeesAndDiarizeBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

            Divider()

            // Segments List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.segments.isEmpty {
                        VStack(spacing: 12) {
                            Text(session.fullText.isEmpty ? L10n.tr(.noTranscript) : session.fullText)
                                .textSelection(.enabled)
                                .font(.body)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(20)
                    } else {
                        ForEach(filteredSegments) { segment in
                            segmentRow(segment)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var attendeesAndDiarizeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Diarization Buttons
                Menu {
                    Button {
                        Task { await runAIDiarization() }
                    } label: {
                        Label(L10n.tr(.aiDiarization), systemImage: "sparkles")
                    }
                    .disabled(isDiarizing || session.segments.isEmpty || geminiAPIKey.isEmpty)

                    Button {
                        runVoiceEmbeddingClustering()
                    } label: {
                        Label(L10n.tr(.offlineDiarization), systemImage: "waveform.badge.magnifyingglass")
                    }
                    .disabled(session.segments.isEmpty)
                } label: {
                    if isDiarizing {
                        ProgressView().controlSize(.small)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.badge.gearshape")
                            Text(L10n.tr(.tabAttendees))
                        }
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)

                // Add Attendee Field
                HStack(spacing: 6) {
                    TextField(L10n.tr(.attendeePlaceholder), text: $newAttendeeName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(maxWidth: 220)
                        .onSubmit { addAttendee() }

                    Button {
                        addAttendee()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newAttendeeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Filter search inside transcript
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    TextField(L10n.tr(.filterTranscript), text: $transcriptFilter)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !transcriptFilter.isEmpty {
                        Button {
                            transcriptFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
                .frame(maxWidth: 200)

                Spacer()
            }

            // Attendee Chips
            if !session.distinctSpeakers.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(session.distinctSpeakers, id: \.self) { speaker in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(SpeakerColorHelper.color(for: speaker))
                                .frame(width: 8, height: 8)

                            Text(speaker)
                                .font(.caption.bold())

                            if session.attendees.contains(speaker) {
                                Button {
                                    transcriptStore.removeAttendee(speaker, from: session.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SpeakerColorHelper.color(for: speaker).opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }

            // Feedback messages
            if let error = diarizeError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let success = diarizeSuccess {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        let isCurrent = audioPlayer.isPlaying &&
            audioPlayer.currentTime >= segment.start &&
            (segment.end > segment.start ? audioPlayer.currentTime < segment.end : true)

        let color = SpeakerColorHelper.color(for: segment.speakerDisplayName)

        return HStack(alignment: .top, spacing: 12) {
            // Speaker Avatar & Menu
            Menu {
                Text(L10n.tr(.changeSpeakerTo))
                ForEach(session.distinctSpeakers, id: \.self) { candidate in
                    if candidate != segment.speakerDisplayName {
                        Button(candidate) {
                            transcriptStore.updateSegmentSpeaker(
                                segmentID: segment.id,
                                speakerName: candidate,
                                in: session.id
                            )
                        }
                    }
                }

                Divider()

                Button(L10n.tr(.editSpeaker)) {
                    activeEditingSegment = segment
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(segment.speakerDisplayName)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 140, alignment: .leading)

            // Segment content & time
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.text)
                    .textSelection(.enabled)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Text(segment.formattedTime)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if session.audioFileURL != nil {
                        Button {
                            audioPlayer.seek(to: segment.start)
                            audioPlayer.play()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 7))
                                Text(L10n.tr(.playFromHere))
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }

    private func addAttendee() {
        let trimmed = newAttendeeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcriptStore.addAttendee(trimmed, to: session.id)
        newAttendeeName = ""
    }

    private func runVoiceEmbeddingClustering() {
        let results = VoiceEmbeddingEngine.shared.cluster(segments: session.segments)
        if results.isEmpty {
            diarizeError = L10n.tr(.offlineDiarizeNoData)
            diarizeSuccess = nil
        } else {
            transcriptStore.applyDiarization(assignments: results, to: session.id)
            let uniqueCount = Set(results.values).count
            diarizeSuccess = L10n.tr(.offlineDiarizeSuccess(uniqueCount))
            diarizeError = nil
        }
    }

    private func runAIDiarization() async {
        isDiarizing = true
        diarizeError = nil
        diarizeSuccess = nil
        defer { isDiarizing = false }

        do {
            let results = try await GeminiService.diarizeSpeakers(
                segments: session.segments,
                attendees: session.attendees,
                apiKey: geminiAPIKey
            )
            transcriptStore.applyDiarization(assignments: results, to: session.id)
            diarizeSuccess = "گویندگان جلسه با موفقیت تفکیک و نام‌گذاری شدند (\(results.count) بخش به‌روزرسانی شد)."
        } catch {
            diarizeError = "خطا در تفکیک گویندگان: \(error.localizedDescription)"
        }
    }
}
