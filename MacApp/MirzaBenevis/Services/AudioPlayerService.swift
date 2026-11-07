import Foundation
import AVFoundation
import Combine

/// Manages in-app audio playback for recorded sessions using native AVFoundation.
final class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var playbackRate: Float = 1.0
    @Published var isLoaded: Bool = false
    @Published var errorMessage: String? = nil

    private var player: AVAudioPlayer?
    private var displayTimer: Timer?
    var isSeeking: Bool = false

    var currentURL: URL? {
        player?.url
    }

    override init() {
        super.init()
    }

    /// Load an audio file from URL. If it's already loaded, keep the current player.
    func load(url: URL) {
        if let player = player, player.url == url {
            return
        }

        stop()

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.enableRate = true
            p.rate = playbackRate
            p.prepareToPlay()
            self.player = p
            self.duration = p.duration
            self.currentTime = 0.0
            self.isLoaded = true
            self.errorMessage = nil
        } catch {
            self.player = nil
            self.isLoaded = false
            self.duration = 0.0
            self.currentTime = 0.0
            self.errorMessage = "خطا در بارگذاری فایل صوتی: \(error.localizedDescription)"
            print("[AudioPlayerService] Failed to load audio from \(url): \(error)")
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let player = player else { return }
        // If reached end, restart from beginning
        if player.currentTime >= player.duration - 0.1 {
            player.currentTime = 0.0
            currentTime = 0.0
        }
        player.rate = playbackRate
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0.0
        player?.currentTime = 0.0
    }

    func seek(to seconds: Double) {
        guard let player = player else { return }
        let target = max(0.0, min(seconds, player.duration))
        player.currentTime = target
        currentTime = target
    }

    func skip(seconds: Double) {
        guard let player = player else { return }
        seek(to: player.currentTime + seconds)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard !self.isSeeking, let player = self.player, self.isPlaying else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPlaying = false
            self.stopTimer()
            self.currentTime = 0.0
            self.player?.currentTime = 0.0
        }
    }

    deinit {
        displayTimer?.invalidate()
        player?.stop()
    }
}
