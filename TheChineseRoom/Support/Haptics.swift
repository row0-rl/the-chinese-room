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

/// A coarse, pulsing rumble while the user's finger drags the card.
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
            let pulseInterval: TimeInterval = 0.08
            let pulseCount = 32
            var events: [CHHapticEvent] = []
            var pulses: [CHHapticParameterCurve] = []
            // Schedule variation on the haptic engine, without a UI timer.
            // A fresh randomized sequence is built for each drag, then loops for long holds.
            for index in 0..<pulseCount {
                let start = Double(index) * pulseInterval
                let strength = Float.random(in: 0.40...0.50)
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: strength),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
                ], relativeTime: start, duration: pulseInterval))
                // Keep the bump and trough proportional to the pulse interval.
                pulses.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                    .init(relativeTime: 0, value: 0.2),
                    .init(relativeTime: pulseInterval * 0.1, value: 1),
                    .init(relativeTime: pulseInterval * 0.35, value: 1),
                    .init(relativeTime: pulseInterval * 0.65, value: 0.2),
                    .init(relativeTime: pulseInterval, value: 0.2)
                ], relativeTime: start))
            }
            let pattern = try CHHapticPattern(events: events, parameterCurves: pulses)
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = Double(pulseCount) * pulseInterval
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
