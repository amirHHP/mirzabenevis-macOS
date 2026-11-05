import SwiftUI

@main
struct MirzaBenevisApp: App {
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

        Window("جلسات", id: "sessions") {
            SessionsWindowView()
                .environmentObject(transcriptStore)
        }
        .defaultSize(width: 900, height: 600)

        Window("تنظیمات", id: "settings") {
            SettingsWindowView()
                .environmentObject(modelManager)
                .environmentObject(updateManager)
        }
        .defaultSize(width: 520, height: 560)
    }
}
