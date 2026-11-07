import SwiftUI
import AppKit

struct SessionAudioPlayerBar: View {
    let audioURL: URL
    @ObservedObject var audioPlayer: AudioPlayerService
    @Binding var scrubTime: Double?

    var body: some View {
        HStack(spacing: 12) {
            // Play / Pause Circle
            Button {
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(audioPlayer.isPlaying ? L10n.tr(.pause) : L10n.tr(.play))

            // Skip backward 5s
            Button {
                audioPlayer.skip(seconds: -5)
            } label: {
                Image(systemName: "gobackward.5")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.tr(.skipBackward5))

            // Skip forward 5s
            Button {
                audioPlayer.skip(seconds: 5)
            } label: {
                Image(systemName: "goforward.5")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.tr(.skipForward5))

            // Current Time
            Text(formatAudioTime(scrubTime ?? audioPlayer.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)

            // Slider / Scrubber
            Slider(
                value: Binding(
                    get: { scrubTime ?? audioPlayer.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(audioPlayer.duration, 0.01)
            ) { editing in
                if editing {
                    scrubTime = audioPlayer.currentTime
                    audioPlayer.isSeeking = true
                } else {
                    if let target = scrubTime {
                        audioPlayer.seek(to: target)
                    }
                    scrubTime = nil
                    audioPlayer.isSeeking = false
                }
            }
            .accentColor(.accentColor)

            // Total Duration
            Text(formatAudioTime(audioPlayer.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)

            // Speed Menu Pill
            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button {
                        audioPlayer.setRate(Float(speed))
                    } label: {
                        HStack {
                            Text(speed == 1.0 ? L10n.tr(.normalSpeed) : String(format: "%.2f×", speed))
                            if abs(Double(audioPlayer.playbackRate) - speed) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(String(format: "%.2f×", audioPlayer.playbackRate))
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .help(L10n.tr(.playbackSpeed))

            // Reveal in Finder Button
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([audioURL])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.tr(.showInFinder))

            // Open with External App
            Button {
                NSWorkspace.shared.open(audioURL)
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.tr(.openExternal))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func formatAudioTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "00:00" }
        let totalSecs = Int(seconds)
        let hours = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}
