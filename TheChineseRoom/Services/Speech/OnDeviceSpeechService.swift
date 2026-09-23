import AVFoundation
import Foundation
import FluidAudio

@MainActor
final class OnDeviceSpeechService: SpeechService {
    private let supertonicRuntime = SupertonicSpeechRuntime()
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var requestID = UUID()

    init() {
        removeObsoleteSpeechAssets()
    }

    #if DEBUG
    static func runSmokeTest() async {
        let supertonicRuntime = SupertonicSpeechRuntime()
        let supertonicSamples = [
            ("en-US", "Hello, where is the bathroom?"),
            ("fr-FR", "Bonjour, où est la salle de bain ?"),
            ("ko-KR", "안녕하세요. 화장실이 어디예요?"),
            ("es-ES", "Hola, ¿dónde está el baño?"),
            ("pt-BR", "Olá, onde fica o banheiro?"),
            ("it-IT", "Buongiorno, dov’è il bagno?"),
            ("ja-JP", "こんにちは。お手洗いはどこですか？"),
            ("ru-RU", "Здравствуйте. Где находится туалет?"),
            ("hi-IN", "नमस्ते। शौचालय कहाँ है?"),
            ("sv-SE", "Hej, var ligger toaletten?")
        ]
        do {
            let directory = URL.documentsDirectory.appendingPathComponent("SpeechChecks")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (locale, text) in supertonicSamples {
                let start = Date()
                let voice = try SupertonicVoice.resolve(nil, locale: locale)
                let wav = try await supertonicRuntime.synthesize(text: text, voice: voice)
                let elapsed = Date().timeIntervalSince(start)
                let player = try AVAudioPlayer(data: wav)
                guard player.duration > 0.1, player.prepareToPlay() else { throw SpeechModelError.emptyAudio }
                let cached = try await supertonicRuntime.synthesize(text: text, voice: voice)
                guard cached == wav else { throw SpeechModelError.emptyAudio }
                try wav.write(to: directory.appendingPathComponent(locale + ".wav"), options: .atomic)
                print("[Speech test] \(locale) engine=\(voice.engineName) voice=\(voice.id) audio=\(player.duration)s synthesis=\(elapsed)s bytes=\(wav.count) cache=PASS")
                fflush(nil)
            }
            guard let mandarinVoice = AVSpeechSynthesisVoice(language: "zh-Hans-CN") else {
                throw SpeechModelError.unsupportedLanguage
            }
            print("[Speech test] zh-Hans-CN engine=Apple system voice default=\(mandarinVoice.name) PASS")
            print("[Speech test] PASS: ten languages via Supertonic; Mandarin via Apple system speech")
            fflush(nil)
        } catch {
            print("[Speech test] FAIL: \(error)")
            fflush(nil)
        }
    }
    #endif

    var isSpeechAudioEnabled: Bool { AVAudioSession.sharedInstance().outputVolume > 0 }

    func availableVoices(localeIdentifier: String) -> [SpeechVoice] {
        if Self.usesSystemSpeech(localeIdentifier) {
            return Self.systemVoices(localeIdentifier: localeIdentifier)
        }
        return SupertonicVoice.voices(for: localeIdentifier).map {
            SpeechVoice(id: $0.id, name: $0.name, language: $0.language, qualityDescription: $0.engineName)
        }
    }

    func prepareSpeechAudio(_ text: String, localeIdentifier: String) async throws {
        if Self.usesSystemSpeech(localeIdentifier) {
            guard AVSpeechSynthesisVoice(language: localeIdentifier) != nil else {
                throw SpeechModelError.unsupportedLanguage
            }
        } else {
            _ = try SupertonicVoice.resolve(nil, locale: localeIdentifier)
        }
    }

    func speak(_ text: String, localeIdentifier: String, voiceIdentifier: String?) async throws {
        let requestStarted = Date()
        let id = UUID()
        requestID = id
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        guard isSpeechAudioEnabled else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)

        if Self.usesSystemSpeech(localeIdentifier) {
            guard let voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
                    .flatMap({ Self.matches($0.language, localeIdentifier) ? $0 : nil })
                    ?? AVSpeechSynthesisVoice(language: localeIdentifier) else {
                throw SpeechModelError.unsupportedLanguage
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            synthesizer.speak(utterance)
            SpeechTimingLog.emit(
                "playback-dispatched engine=Apple system locale=\(localeIdentifier) voice=\(voice.identifier) "
                    + "request=\(SpeechTimingLog.seconds(since: requestStarted))s chars=\(text.count)"
            )
            return
        }

        let voice = try SupertonicVoice.resolve(voiceIdentifier, locale: localeIdentifier)
        let wav = try await supertonicRuntime.synthesize(text: text, voice: voice)
        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        let nextPlayer = try AVAudioPlayer(data: wav)
        guard nextPlayer.prepareToPlay(), nextPlayer.play() else { throw SpeechModelError.playbackFailed }
        player = nextPlayer
        SpeechTimingLog.emit(
            "playback-start engine=\(voice.engineName) locale=\(localeIdentifier) voice=\(voice.id) "
                + "request=\(SpeechTimingLog.seconds(since: requestStarted))s "
                + "audio=\(SpeechTimingLog.seconds(nextPlayer.duration))s chars=\(text.count)"
        )
    }

    private static func usesSystemSpeech(_ localeIdentifier: String) -> Bool {
        Locale.Language(identifier: localeIdentifier).languageCode?.identifier == "zh"
    }

    private static func matches(_ voiceLocale: String, _ requestedLocale: String) -> Bool {
        Locale.Language(identifier: voiceLocale).languageCode
            == Locale.Language(identifier: requestedLocale).languageCode
    }

    private static func systemVoices(localeIdentifier: String) -> [SpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { matches($0.language, localeIdentifier) }
            .map {
                SpeechVoice(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    qualityDescription: qualityDescription($0.quality)
                )
            }
            .sorted {
                let order = ["Premium": 2, "Enhanced": 1, "Default": 0]
                let lhs = order[$0.qualityDescription, default: 0]
                let rhs = order[$1.qualityDescription, default: 0]
                return lhs == rhs
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : lhs > rhs
            }
    }

    private static func qualityDescription(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Default"
        }
    }

    private func removeObsoleteSpeechAssets() {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let modelsDirectory = applicationSupport
            .appendingPathComponent("fluidaudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        for name in ["vits-melo-tts-zh_en", "kokoro", "kokoro-82m-coreml"] {
            try? FileManager.default.removeItem(
                at: modelsDirectory.appendingPathComponent(name, isDirectory: true)
            )
        }
        try? FileManager.default.removeItem(
            at: applicationSupport.appendingPathComponent("Qwen3TTS", isDirectory: true)
        )
    }
}

private struct SupertonicVoice: Sendable {
    let id: String
    let name: String
    let language: String
    let engineName: String
    let modelVoice: Supertonic3Voice
    let modelLanguage: String

    static let catalog: [SupertonicVoice] = {
        let languages = [
            ("en", "en-US"),
            ("fr", "fr-FR"),
            ("ko", "ko-KR"),
            ("es", "es-ES"),
            ("pt", "pt-BR"),
            ("it", "it-IT"),
            ("ja", "ja-JP"),
            ("ru", "ru-RU"),
            ("hi", "hi-IN"),
            ("sv", "sv-SE")
        ]
        let voices = [Supertonic3Voice.default] + Supertonic3Voice.allCases.filter { $0 != .default }
        return languages.flatMap { code, locale in
            voices.map { voice in
                let gender = voice.rawValue.hasPrefix("F") ? "Female" : "Male"
                return SupertonicVoice(
                    id: "supertonic3:\(code):\(voice.rawValue)",
                    name: "\(gender) \(voice.rawValue.dropFirst())",
                    language: locale,
                    engineName: "Supertonic 3 INT4",
                    modelVoice: voice,
                    modelLanguage: code
                )
            }
        }
    }()

    static func voices(for locale: String) -> [SupertonicVoice] {
        let language = Locale.Language(identifier: locale).languageCode?.identifier
        return catalog.filter { Locale.Language(identifier: $0.language).languageCode?.identifier == language }
    }

    static func resolve(_ id: String?, locale: String) throws -> SupertonicVoice {
        let voices = voices(for: locale)
        guard let voice = voices.first(where: { $0.id == id }) ?? voices.first else {
            throw SpeechModelError.unsupportedLanguage
        }
        return voice
    }
}

private actor SupertonicSpeechRuntime {
    private var model: Supertonic3Manager?
    private var loadedStyles: [Supertonic3Voice: Supertonic3VoiceStyle] = [:]
    private var cachedKey: String?
    private var cachedAudio: Data?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    func synthesize(text: String, voice: SupertonicVoice) async throws -> Data {
        let requestStarted = Date()
        await acquire()
        defer { release() }
        let queueDuration = Date().timeIntervalSince(requestStarted)
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechModelError.emptyAudio
        }
        let key = voice.id + "\n" + text
        if cachedKey == key, let cachedAudio {
            SpeechTimingLog.emit(
                "cache-hit engine=\(voice.engineName) locale=\(voice.language) voice=\(voice.id) "
                    + "queue=\(SpeechTimingLog.seconds(queueDuration))s total=\(SpeechTimingLog.seconds(since: requestStarted))s"
            )
            return cachedAudio
        }

        var setupDuration: TimeInterval = 0
        if model == nil {
            let setupStarted = Date()
            SpeechTimingLog.emit("model-setup-start engine=\(voice.engineName)")
            try excludeSpeechAssetsFromBackup()
            model = try await Supertonic3Manager.downloadAndCreate(vectorEstimator: .aneBucketed(.int4))
            setupDuration = Date().timeIntervalSince(setupStarted)
            SpeechTimingLog.emit(
                "model-setup-complete engine=\(voice.engineName) elapsed=\(SpeechTimingLog.seconds(setupDuration))s"
            )
        }
        guard let model else { throw SpeechModelError.modelLoadFailed }
        let styleStarted = Date()
        let style: Supertonic3VoiceStyle
        if let loaded = loadedStyles[voice.modelVoice] {
            style = loaded
        } else {
            style = try await Supertonic3ResourceDownloader.loadVoiceStyle(voice.modelVoice)
            loadedStyles[voice.modelVoice] = style
        }
        let styleDuration = Date().timeIntervalSince(styleStarted)
        let generationStarted = Date()
        let result = try await model.synthesize(
            text: text,
            language: voice.modelLanguage,
            style: style
        )
        let generationDuration = Date().timeIntervalSince(generationStarted)
        guard !result.samples.isEmpty, result.samples.allSatisfy(\.isFinite) else {
            throw SpeechModelError.emptyAudio
        }
        let encodingStarted = Date()
        let wav = WaveEncoder.encode(result.samples, rate: UInt32(Supertonic3Constants.sampleRate))
        let encodingDuration = Date().timeIntervalSince(encodingStarted)
        try Task.checkCancellation()
        guard wav.count > 44 else { throw SpeechModelError.emptyAudio }
        cachedKey = key
        cachedAudio = wav
        SpeechTimingLog.emit(
            "generated engine=\(voice.engineName) locale=\(voice.language) voice=\(voice.id) "
                + "queue=\(SpeechTimingLog.seconds(queueDuration))s setup=\(SpeechTimingLog.seconds(setupDuration))s "
                + "style=\(SpeechTimingLog.seconds(styleDuration))s generation=\(SpeechTimingLog.seconds(generationDuration))s "
                + "wav=\(SpeechTimingLog.seconds(encodingDuration))s total=\(SpeechTimingLog.seconds(since: requestStarted))s "
                + "audio=\(SpeechTimingLog.seconds(TimeInterval(result.duration)))s chars=\(text.count)"
        )
        return wav
    }

    private func excludeSpeechAssetsFromBackup() throws {
        var directory = try TtsCacheDirectory.ensure()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

}

private enum WaveEncoder {
    static func encode(_ samples: [Float], rate: UInt32) -> Data {
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        func u16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        ascii("RIFF"); u32(36 + byteCount); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        ascii("data"); u32(byteCount)
        for sample in samples {
            u16(UInt16(bitPattern: Int16(max(-1, min(1, sample)) * 32767)))
        }
        return data
    }
}

private enum SpeechTimingLog {
    static func emit(_ message: String) {
        print("[TTS timing] \(message)")
        fflush(nil)
    }

    static func seconds(since start: Date) -> String {
        seconds(Date().timeIntervalSince(start))
    }

    static func seconds(_ duration: TimeInterval) -> String {
        String(format: "%.3f", duration)
    }

}

private enum SpeechModelError: LocalizedError {
    case unsupportedLanguage, modelLoadFailed, emptyAudio, playbackFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage: "No on-device speech voice is available for this language."
        case .modelLoadFailed: "The on-device speech model could not be loaded."
        case .emptyAudio: "The speech model could not generate audio for this text."
        case .playbackFailed: "The generated speech could not be played."
        }
    }
}
