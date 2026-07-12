import Foundation

struct OpenAIResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let text: OpenAITextConfiguration
    let store: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case text
        case store
    }
}

struct OpenAITextConfiguration: Encodable {
    let format: OpenAITextFormat
}

struct OpenAITextFormat: Encodable {
    let type: String
    let name: String
    let strict: Bool
    let schema: [String: JSONValue]
}

struct OpenAIResponse: Decodable {
    let status: String
    let error: ResponseError?
    let incompleteDetails: IncompleteDetails?
    let output: [OutputItem]

    enum CodingKeys: String, CodingKey {
        case status
        case error
        case incompleteDetails = "incomplete_details"
        case output
    }

    var outputText: String? {
        output
            .flatMap(\.content)
            .first { $0.type == "output_text" }?
            .text
    }

    struct OutputItem: Decodable {
        let content: [ContentPart]

        enum CodingKeys: String, CodingKey {
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.content = (try? container.decode([ContentPart].self, forKey: .content)) ?? []
        }
    }

    struct ContentPart: Decodable {
        let type: String
        let text: String?
    }

    struct ResponseError: Decodable {
        let code: String?
        let message: String?
    }

    struct IncompleteDetails: Decodable {
        let reason: String?
    }
}

struct OpenAIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

struct TranslationPayload {
    let sourceText: String
    let normalizedSourceText: String
    let targetText: String
    let examples: [ExamplePayload]?

    static func decode(from data: Data, languageMode: LanguageMode) throws -> TranslationPayload {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw payloadError("Expected generated message JSON to be an object.")
        }

        let sourceKey = languageMode.source.schemaKey
        let targetKey = languageMode.target.schemaKey

        let examples = try optionalArrayValue(dictionary, key: "examples")?.map { example in
            ExamplePayload(
                sourceText: try stringValue(example, key: sourceKey),
                targetText: try stringValue(example, key: targetKey)
            )
        }
        let sourceText = try stringValue(dictionary, key: sourceKey)

        return TranslationPayload(
            sourceText: sourceText,
            normalizedSourceText: sourceText,
            targetText: try stringValue(dictionary, key: targetKey),
            examples: examples
        )
    }

    struct ExamplePayload {
        let sourceText: String
        let targetText: String
    }
}

struct AlignmentPayload {
    let literalChunks: [LiteralChunkPayload]

    static func decode(from data: Data, languageMode: LanguageMode) throws -> AlignmentPayload {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw payloadError("Expected generated alignment JSON to be an object.")
        }

        let sourceKey = languageMode.source.schemaKey
        let targetKey = languageMode.target.schemaKey
        let literalChunkObjects = try arrayValue(dictionary, key: "literalChunks")
        let literalChunks = try literalChunkObjects.map { chunk in
            LiteralChunkPayload(
                targetText: try stringValue(chunk, key: targetKey),
                literalText: try stringValue(chunk, key: sourceKey)
            )
        }

        return AlignmentPayload(
            literalChunks: literalChunks
        )
    }

    struct LiteralChunkPayload {
        let targetText: String
        let literalText: String
    }
}

struct LearningMessagePayload {
    let translation: TranslationPayload
    let alignment: AlignmentPayload

    func learningMessage(originalInput: String?) -> LearningMessage {
        LearningMessage(
            sourceText: originalInput ?? translation.sourceText,
            normalizedSourceText: translation.normalizedSourceText,
            targetText: translation.targetText,
            literalMeaning: alignment.literalChunks.map(\.literalText).joined(separator: " "),
            literalChunks: alignment.literalChunks.map { MessageLiteralChunk(targetText: $0.targetText, literalText: $0.literalText) },
            examples: translation.examples?.map { MessageExample(sourceText: $0.sourceText, targetText: $0.targetText) }
        )
    }
}

private func stringValue(_ dictionary: [String: Any], key: String) throws -> String {
    guard let value = dictionary[key] as? String else {
        throw payloadError("Expected generated message field '\(key)' to be a string.")
    }

    return value
}

private func arrayValue(_ dictionary: [String: Any], key: String) throws -> [[String: Any]] {
    guard let value = dictionary[key] as? [[String: Any]] else {
        throw payloadError("Expected generated message field '\(key)' to be an array of objects.")
    }

    return value
}

private func optionalArrayValue(_ dictionary: [String: Any], key: String) throws -> [[String: Any]]? {
    guard let value = dictionary[key], !(value is NSNull) else {
        return nil
    }

    guard let array = value as? [[String: Any]] else {
        throw payloadError("Expected generated message field '\(key)' to be null or an array of objects.")
    }

    return array
}

private func payloadError(_ message: String) -> NSError {
    NSError(
        domain: "TheChineseRoom.LearningMessagePayload",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
}
