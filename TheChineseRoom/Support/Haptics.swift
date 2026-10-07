import CoreHaptics
import UIKit

@MainActor
enum Haptics {
    private static let messageImpact = UIImpactFeedbackGenerator(style: .heavy)

    static func prepareMessageChange() {
        messageImpact.prepare()
    }

    static func messageChanged() {
        messageImpact.impactOccurred()
    }

    static func dictationStarted() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}

/// One sustained, low-sharpness rumble while the user's finger drags the card.
@MainActor
final class CardDragHaptics {
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var player: (any CHHapticAdvancedPatternPlayer)?
    private var isStarting = false
    private var isRunning = false
    private var wantsRumble = false
    private var startID = UUID()

    func prepare() {
        guard supported, !isStarting, !isRunning else { return }
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = true
                engine.stoppedHandler = { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.engineStopped()
                    }
                }
                engine.resetHandler = { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let resumeRumble = self.wantsRumble
                        self.engineStopped()
                        if resumeRumble { self.beginRumble() }
                    }
                }
                self.engine = engine
            }
            guard let engine else { return }
            isStarting = true
            let id = UUID()
            startID = id
            // Warm up asynchronously so the first drag update never waits for hardware.
            engine.start { [weak self] error in
                let didStart = error == nil
                Task { @MainActor [weak self] in
                    guard let self, self.startID == id else { return }
                    self.isStarting = false
                    self.isRunning = didStart
                    if didStart { self.playRumbleIfNeeded() }
                    else { self.wantsRumble = false }
                }
            }
        } catch {
            wantsRumble = false
        }
    }

    func beginRumble() {
        guard supported, !wantsRumble else { return }
        wantsRumble = true
        Haptics.prepareMessageChange()
        prepare()
        playRumbleIfNeeded()
    }

    func stopRumble() {
        wantsRumble = false
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    private func playRumbleIfNeeded() {
        guard wantsRumble, isRunning, player == nil, let engine else { return }
        do {
            let duration: TimeInterval = 30
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
            ], relativeTime: 0, duration: duration)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = duration
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
        } catch {
            stopRumble()
        }
    }

    private func engineStopped() {
        startID = UUID()
        player = nil
        isStarting = false
        isRunning = false
        wantsRumble = false
    }
}
