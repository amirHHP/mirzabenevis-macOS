import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let reopenNotification = Notification.Name("MirzaBenevisReopenApp")

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // If sessions window is already in windows list, bring it to front
            if let window = sender.windows.first(where: {
                $0.identifier?.rawValue == "sessions" ||
                $0.title.contains("جلسات") ||
                $0.title.contains("Meetings")
            }) {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                NotificationCenter.default.post(name: Self.reopenNotification, object: nil)
            }
        } else {
            sender.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}

@main
struct MirzaBenevisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var transcriptStore: TranscriptStore
    @StateObject private var coordinator: RecordingCoordinator
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var updateManager = UpdateManager.shared

    init() {
        let store = TranscriptStore()
        _transcriptStore = StateObject(wrappedValue: store)
        _coordinator = StateObject(wrappedValue: RecordingCoordinator(transcriptStore: store))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(coordinator: coordinator)
                .environmentObject(transcriptStore)
                .environmentObject(modelManager)
                .environmentObject(updateManager)
        } label: {
            Image(systemName: coordinator.isActive ? "mic.fill" : "waveform.circle")
                .symbolEffect(.pulse, isActive: coordinator.isActive)
        }
        .menuBarExtraStyle(.window)

        Window(LanguageManager.shared.currentLanguage == .english ? "Meetings & Notes" : "جلسات و یادداشت‌ها", id: "sessions") {
            SessionsWindowView()
                .environmentObject(transcriptStore)
        }
        .defaultSize(width: 960, height: 640)

        Window(LanguageManager.shared.currentLanguage == .english ? "Settings" : "تنظیمات", id: "settings") {
            SettingsWindowView()
                .environmentObject(modelManager)
                .environmentObject(updateManager)
        }
        .defaultSize(width: 520, height: 560)
    }
}
