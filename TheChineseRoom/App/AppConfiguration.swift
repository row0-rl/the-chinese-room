import Foundation

struct AppConfiguration {
    var openAIConfiguration: OpenAIMessageService.Configuration?
    var speechConfiguration: OpenAISpeechService.Configuration?
    var dictationConfiguration: OpenAIDictationService.Configuration?

    static var current: AppConfiguration {
        let apiKey = Bundle.main.trimmedInfoValue(forKey: "OPENAI_API_KEY")
            ?? ProcessInfo.processInfo.trimmedEnvironmentValue(forKey: "OPENAI_API_KEY")
        let model = Bundle.main.trimmedInfoValue(forKey: "OPENAI_MODEL")
            ?? ProcessInfo.processInfo.trimmedEnvironmentValue(forKey: "OPENAI_MODEL")
            ?? "gpt-5.4-mini"
        let speechModel = Bundle.main.trimmedInfoValue(forKey: "OPENAI_TTS_MODEL")
            ?? ProcessInfo.processInfo.trimmedEnvironmentValue(forKey: "OPENAI_TTS_MODEL")
            ?? "gpt-4o-mini-tts"
        let speechVoice = Bundle.main.trimmedInfoValue(forKey: "OPENAI_TTS_VOICE")
            ?? ProcessInfo.processInfo.trimmedEnvironmentValue(forKey: "OPENAI_TTS_VOICE")
            ?? "alloy"
        let transcriptionModel = Bundle.main.trimmedInfoValue(forKey: "OPENAI_TRANSCRIPTION_MODEL")
            ?? ProcessInfo.processInfo.trimmedEnvironmentValue(forKey: "OPENAI_TRANSCRIPTION_MODEL")
            ?? "gpt-realtime-whisper"

        guard let apiKey else {
            return AppConfiguration(openAIConfiguration: nil, speechConfiguration: nil, dictationConfiguration: nil)
        }

        return AppConfiguration(
            openAIConfiguration: OpenAIMessageService.Configuration(apiKey: apiKey, model: model),
            speechConfiguration: OpenAISpeechService.Configuration(apiKey: apiKey, model: speechModel, voice: speechVoice),
            dictationConfiguration: OpenAIDictationService.Configuration(apiKey: apiKey, transcriptionModel: transcriptionModel)
        )
    }
}
