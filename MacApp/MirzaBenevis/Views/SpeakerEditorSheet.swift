import SwiftUI

struct SpeakerEditorSheet: View {
    let segment: TranscriptSegment
    let session: TranscriptionSession
    let onSave: (String, Bool) -> Void

    @State private var name: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var langManager = LanguageManager.shared

    init(segment: TranscriptSegment, session: TranscriptionSession, onSave: @escaping (String, Bool) -> Void) {
        self.segment = segment
        self.session = session
        self.onSave = onSave
        _name = State(initialValue: segment.speakerDisplayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr(.editSpeakerTitle))
                .font(.headline)

            Text(L10n.tr(.currentSpeakerName(segment.speakerDisplayName)))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(L10n.tr(.newSpeakerNamePlaceholder), text: $name)
                .textFieldStyle(.roundedBorder)

            if !session.distinctSpeakers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr(.quickSelectAttendee))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(session.distinctSpeakers, id: \.self) { candidate in
                            Button(candidate) {
                                name = candidate
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(L10n.tr(.cancel), role: .cancel) {
                    dismiss()
                }

                Spacer()

                Button(L10n.tr(.applyThisSegmentOnly)) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, false)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(L10n.tr(.applyGlobally)) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, true)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .environment(\.layoutDirection, langManager.layoutDirection)
    }
}
