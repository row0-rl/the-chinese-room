import Foundation
import Observation
import Translation

protocol TextTranslationService {
    func translate(_ text: String, languageMode: LanguageMode) async throws -> String
}

/// Requests are executed only inside SwiftUI's translationTask, so the system
/// can present language downloads and sessions never escape their view lifetime.
@MainActor @Observable
final class AppleTranslationService: TextTranslationService {
    struct Request: Identifiable {
        let id: UUID
        let text: String
        let languageMode: LanguageMode
    }
    private struct Pending {
        let request: Request
        let continuation: CheckedContinuation<String, Error>
    }
    private var pending: [Pending] = []
    var currentRequest: Request? { pending.first?.request }

    func translate(_ text: String, languageMode: LanguageMode) async throws -> String {
        try Task.checkCancellation()
        let request = Request(id: UUID(), text: text, languageMode: languageMode)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append(Pending(request: request, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in self.finish(request.id, result: .failure(CancellationError())) }
        }
    }

    func perform(_ request: Request, using session: TranslationSession) async {
        guard currentRequest?.id == request.id else { return }
        do {
            try Task.checkCancellation()
            let response = try await session.translate(request.text)
            try Task.checkCancellation()
            guard !response.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationError.nothingToTranslate
            }
            #if DEBUG
            FileHandle.standardError.write(Data("[TheChineseRoom] Apple translated:\n\(response.targetText)\n".utf8))
            #endif
            finish(request.id, result: .success(response.targetText))
        } catch {
            finish(request.id, result: .failure(error))
        }
    }

    func cancelAll() {
        let requests = pending
        pending.removeAll()
        for request in requests { request.continuation.resume(throwing: CancellationError()) }
    }

    private func finish(_ id: UUID, result: Result<String, Error>) {
        guard let index = pending.firstIndex(where: { $0.request.id == id }) else { return }
        pending.remove(at: index).continuation.resume(with: result)
    }
}
