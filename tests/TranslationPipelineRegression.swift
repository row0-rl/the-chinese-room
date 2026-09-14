import Foundation
import FoundationModels

actor Events {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
}
actor AppleMessageRuntime {
    let events: Events
    let scenario: String
    var segmentationCalls = 0
    var glossCalls = 0
    init(events: Events, scenario: String = "normal") { self.events = events; self.scenario = scenario }
    func segmentText(to prompt: String, languages: [LanguageProfile]) async throws -> String {
        precondition(prompt.contains("J'ai faim."))
        precondition(prompt.contains("inserting |"))
        await events.append("segmentation")
        segmentationCalls += 1
        if scenario == "throws" { throw TestFailure.unavailable }
        if scenario == "cancel" { throw CancellationError() }
        if scenario == "badSegmentation" || (scenario == "repair" && segmentationCalls == 1) { return "J'ai" }
        if scenario == "emptyChunk" { return "J'ai|| faim." }
        if scenario == "commentary" { return "Here are the chunks: J'ai| faim." }
        if scenario == "repair" { precondition(prompt.contains("Previous output:") && prompt.contains("faim")) }
        return "J'ai| faim."
    }
    func respond<T: Generable>(to prompt: String, generating type: T.Type, languages: [LanguageProfile]) async throws -> T {
        if type == GeneratedSource.self {
            precondition(!prompt.contains("French"))
            await events.append("source")
            return try T(GeneratedContent(json: #"{"sourceText":"I am hungry."}"#))
        }
        precondition(prompt.contains("J'ai faim."))
        precondition(type == GeneratedGlosses.self)
        await events.append("glosses")
        glossCalls += 1
        precondition(prompt.contains("1: \" faim.\""))
        if scenario == "repair" && glossCalls == 1 {
            return try T(GeneratedContent(json: #"{"glosses":[{"chunkID":0,"literalText":"I have"}]}"#))
        }
        if scenario == "repair" {
            precondition(prompt.contains("Requested chunk IDs: 1"))
            precondition(prompt.contains("Previous output:"))
            return try T(GeneratedContent(json: #"{"glosses":[{"chunkID":0,"literalText":"DO NOT OVERWRITE"},{"chunkID":1,"literalText":"hunger"}]}"#))
        }
        if scenario == "duplicate" {
            return try T(GeneratedContent(json: #"{"glosses":[{"chunkID":0,"literalText":"I"},{"chunkID":0,"literalText":"have"},{"chunkID":99,"literalText":"unknown"}]}"#))
        }
        // Deliberately shuffled: stable IDs, not response order, bind the glosses.
        return try T(GeneratedContent(json: #"{"glosses":[{"chunkID":1,"literalText":"hunger"},{"chunkID":0,"literalText":"I have"}]}"#))
    }
}
enum FoundationModelsServiceError: Error { case languageMismatch(LanguageProfile) }
enum TestFailure: Error { case unavailable }
struct Translator: TextTranslationService {
    let events: Events
    var fails = false
    func translate(_ text: String, languageMode: LanguageMode) async throws -> String {
        precondition(text == "I am hungry.")
        await events.append("apple")
        if fails { throw TestFailure.unavailable }
        return "J'ai faim."
    }
}

@main struct TranslationPipelineRegression {
    @MainActor static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("Translation queue failed to advance")
    }
    @MainActor static func main() async throws {
        let events = Events()
        let service = FoundationModelsMessageService(runtime: AppleMessageRuntime(events: events), translator: Translator(events: events))
        let card = try await service.message(for: "Me be hungry", languageMode: .defaultMode)
        precondition(card.sourceText == "Me be hungry")
        precondition(card.normalizedSourceText == "I am hungry.")
        precondition(card.targetText == "J'ai faim.")
        precondition(card.literalChunks.count == 2)
        precondition(card.literalChunks.map(\.targetText).joined() == card.targetText)
        let sequence = await events.values
        precondition(sequence == ["source", "apple", "segmentation", "glosses"])
        let failedEvents = Events()
        let failing = FoundationModelsMessageService(runtime: AppleMessageRuntime(events: failedEvents), translator: Translator(events: failedEvents, fails: true))
        do {
            _ = try await failing.message(for: "Me be hungry", languageMode: .defaultMode)
            preconditionFailure("Translation failure was swallowed")
        } catch TestFailure.unavailable { }
        let failedSequence = await failedEvents.values
        precondition(failedSequence == ["source", "apple"])

        for scenario in ["repair", "badSegmentation", "emptyChunk", "commentary", "duplicate", "throws"] {
            let trace = Events()
            let candidate = FoundationModelsMessageService(runtime: AppleMessageRuntime(events: trace, scenario: scenario), translator: Translator(events: trace))
            let result = try await candidate.message(for: "Me be hungry", languageMode: .defaultMode)
            precondition(result.targetText == "J'ai faim.")
            let calls = await trace.values
            if scenario == "repair" {
                precondition(result.literalChunks.map(\.literalText) == ["I have", "hunger"])
                precondition(calls == ["source", "apple", "segmentation", "segmentation", "glosses", "glosses"])
            } else {
                precondition(result.literalChunks.isEmpty)
                if ["badSegmentation", "emptyChunk", "commentary"].contains(scenario) { precondition(!calls.contains("glosses")) }
                if scenario == "duplicate" { precondition(calls.filter { $0 == "glosses" }.count == 2) }
            }
        }
        let canceledTrace = Events()
        let canceled = FoundationModelsMessageService(runtime: AppleMessageRuntime(events: canceledTrace, scenario: "cancel"), translator: Translator(events: canceledTrace))
        do {
            _ = try await canceled.message(for: "Me be hungry", languageMode: .defaultMode)
            preconditionFailure("Cancellation was swallowed")
        } catch is CancellationError { }

        let bridge = AppleTranslationService()
        let first = Task { try await bridge.translate("first", languageMode: .defaultMode) }
        await waitUntil { bridge.currentRequest?.text == "first" }
        let second = Task { try await bridge.translate("second", languageMode: .defaultMode) }
        // Give the second caller a chance to enqueue before canceling the first.
        await Task.yield()
        first.cancel()
        do { _ = try await first.value; preconditionFailure("Canceled translation returned") }
        catch is CancellationError { }
        await waitUntil { bridge.currentRequest?.text == "second" }
        bridge.cancelAll()
        do { _ = try await second.value; preconditionFailure("Detached view left translation running") }
        catch is CancellationError { }
        precondition(bridge.currentRequest == nil)
        print("PASS: four-stage pipeline, segmentation gate/repair, gloss IDs/targeted repair, failure isolation, and cancellation")
    }
}
