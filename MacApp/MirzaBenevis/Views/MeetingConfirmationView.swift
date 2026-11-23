import SwiftUI
import AppKit

@MainActor
struct MeetingConfirmationView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 44, height: 44)

                    Image(systemName: "clock.badge.questionmark.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr(.hourlyCheckTitle))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(L10n.tr(.hourlyCheckMessage(coordinator.hourlyConfirmationHours)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Countdown badge
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(coordinator.autoStopCountdownSeconds / 60):\(String(format: "%02d", coordinator.autoStopCountdownSeconds % 60))")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)

                    Text("توقف خودکار")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Notice
            Text(L10n.tr(.hourlyCheckAutoStopNotice(coordinator.autoStopCountdownSeconds)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(2)

            Divider()

            // Action Buttons
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    coordinator.confirmStopRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text(L10n.tr(.hourlyCheckStop))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    coordinator.confirmContinueRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text(L10n.tr(.hourlyCheckContinue))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.layoutDirection, langManager.layoutDirection)
    }
}

@MainActor
final class MeetingConfirmationPanel {
    static let shared = MeetingConfirmationPanel()
    private var panel: NSPanel?

    func show(coordinator: RecordingCoordinator) {
        if panel == nil {
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 210),
                styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.titleVisibility = .hidden
            newPanel.titlebarAppearsTransparent = true
            newPanel.isMovableByWindowBackground = true
            newPanel.standardWindowButton(.closeButton)?.isHidden = true
            newPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            newPanel.standardWindowButton(.zoomButton)?.isHidden = true
            self.panel = newPanel
        }

        guard let panel = panel else { return }

        let contentView = MeetingConfirmationView(coordinator: coordinator)
        panel.contentView = NSHostingView(rootView: contentView)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSSound(named: "Purr")?.play()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
