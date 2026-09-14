# Chunk-by-chunk literal translation improvement plan

Status: proposed; documentation only. Prepared 2026-09-12 from the current repository. No implementation or deployment is authorized by this plan.

## Goal and scope

Help learners understand how the **target expression** is constructed, using concise explanations in their selected original/source language. Preserve the natural translation, target order, and useful grammatical detail. A literal explanation may sound unnatural in the source language; it must not silently become another fluent sentence translation.

Keep generation and evaluation runs on-device with Apple Foundation Models. Cloud-model comparisons are an optional future decision requiring separate authorization, not a dependency or automatic fallback. Preserve existing pager, localization, and speech behavior.

## Current behavior and limitations

- `FoundationModelsMessageService.swift` generates a normalized source sentence, natural target translation, and optional examples in one session. A separate session generates alignment. Alignment receives the target and language pair, but not the normalized source sentence, so useful sense-disambiguating context is lost.
- `MessageGenerationPrompt.swift` asks for small meaning units and conditionally attached particles, endings, auxiliaries, and fixed expressions. The generated schema instead describes `literalText` as a “direct word-by-word” counterpart. These competing instructions leave segmentation and explanation style underspecified.
- Validation requires a nonempty list and target reconstruction through concatenation, with or without spaces, after whitespace and some punctuation-spacing normalization. It does not check empty individual glosses, misleading senses, omitted grammatical meaning, or pedagogical usefulness.
- One retry receives the structural error, but not the failed candidate. If that retry is also invalid, the service creates one whole-target chunk using concatenated glosses from the invalid retry. This disguises failure without establishing correctness.
- Thrown alignment errors currently prevent the completed natural translation from becoming a returned `LearningMessage`. The translation-ready callback can already run before alignment finishes; changing delivery must not duplicate speech or allow stale results to affect another card.
- `LearningMessage` defaults missing chunks to a whole-expression gloss. Persisted messages have no alignment availability or provenance field. An explicit unavailable state must survive both initialization and persistence.

## Phase 1 — Define quality and capture a baseline

Create a small, versioned corpus before changing prompts: **12 cases per direction, 144 total**, covering every distinct direction among English, French, Simplified Chinese, and Korean. A source row must not be treated as equivalent to its reversed direction.

Within each direction include ordinary phrases, idioms, negation/scope, particles or endings where applicable, ambiguous senses with context, mixed-language learner input, and punctuation. Also include contractions, unspaced scripts, and a longer expression across the relevant directions. Cases may cover multiple categories. Keep a development subset and a held-out subset separated by expression family.

Each case records raw input, intended meaning, normalized source, acceptable natural translation(s), acceptable chunkings, gloss alternatives, grammatical requirements, and known misleading outputs. Use bilingual review for that direction; explicitly mark unreviewed cases. Do not require one exact gloss string where several are defensible.

Evaluate alignment with fixed reviewed translations first, then run end-to-end generation to distinguish translation errors from alignment errors. Record baseline structural acceptance, semantic errors, usefulness, fallback rate, and latency. Repeat each case at least three times to expose output variability.

## Phase 2 — Resolve the prompt contract

Pass the normalized source sentence alongside the fixed target expression. Instruct the model to use the source **only to resolve intended sense and context**: do not align to source word order, invent a source-word counterpart for every target morpheme, or rewrite the target to make it fit.

Adopt one shared definition of a chunk: a small, contiguous target meaning or grammatical unit that supports a useful source-language gloss. Make prompt and schema agree. Add short target-specific examples, reviewed across all source languages:

| Target language | Proposed rule to evaluate |
| --- | --- |
| English | Preserve useful auxiliary and negation distinctions; explain contractions and phrasal verbs without arbitrary splitting. |
| French | Preserve clitics, negation, and auxiliary structure where useful; group contractions when splitting would require inventing target characters. |
| Simplified Chinese | Segment meaningful words and constructions, not characters indiscriminately; explain aspect and sentence particles by function when there is no direct lexical counterpart. |
| Korean | Explain relevant particles and endings without forcing every surface form into standalone translated words; retain a larger unit when a faithful surface split is impractical. |

For idioms, group the smallest useful fixed expression. Distinguish its structural/literal reading from its contextual meaning through a short optional note; do not present the idiomatic paraphrase as a literal gloss. Test whether this distinction is understandable on a small card.

Run incremental comparisons: baseline; added source context; consistent chunk rules; then target-specific examples. Retain changes only when reviewed results support them. More instructions or examples do not inherently improve this model.

## Phase 3 — Strengthen structure without claiming semantic proof

Keep required fields small: exact `targetText` and a concise source-language `literalText`. Evaluate an optional `note` for grammar or idiom explanation; add it only if the corpus demonstrates value relative to generation cost and display complexity. Avoid model-reported confidence scores or elaborate linguistic taxonomies without a demonstrated consumer.

Replace permissive reconstruction with a deterministic coverage check against the immutable target: nonempty target spans and glosses; ordered, contiguous coverage; no omitted or duplicated material; preserved punctuation. Specify whitespace handling explicitly. Derive span locations and separators locally through sequential matching where possible rather than asking the model to count Unicode offsets. Keep Unicode segmentation consistent with Swift strings and test repeated substrings, apostrophes, and unspaced text.

Structural validation can establish coverage and field integrity. It **cannot establish** that a gloss captures the correct sense, negation, grammatical function, or idiomatic meaning. Use human-reviewed evaluation for those claims. Language/script heuristics may flag review candidates but should not reject legitimate names or mixed-language glosses blindly.

## Phase 4 — Bounded repair and honest partial success

Allow one alignment attempt plus at most one repair. Give repair the unchanged normalized source, target, failed candidate, and precise validation errors. Do not regenerate the natural translation during repair. After another invalid result or a non-cancellation alignment error, return the natural translation and examples with alignment explicitly unavailable. Never concatenate rejected glosses into a substitute chunk.

Introduce a small alignment state such as `pending`, `available`, and `unavailable` if staged delivery is justified. First implement partial success after bounded alignment completes; separately assess showing the natural translation immediately and attaching chunks later. That second step requires store/persistence coordination and is not merely a prompt edit.

Localize the unavailable explanation and offer an explicit retry when appropriate. Keep the natural target visible and pronunciation usable. Treat cancellation as cancellation, not as an error card. Associate late alignment results with message ID and language mode; ignore stale results after navigation or mode changes.

Update persistence decoding compatibly. Preserve legacy messages without declaring old glosses newly verified; distinguish legacy provenance or defer their regeneration to an explicit action. Remove initializer behavior that recreates a whole-expression gloss for an unavailable alignment.

## Phase 5 — Acceptance and rollout

Proposed gates, to confirm after baseline measurement:

- Every alignment displayed as available passes structural validation. Fault-injection tests prove invalid/empty results and repair exhaustion produce an unavailable state, never a manufactured gloss.
- All 12 directions are reviewed. Target at least 95% acceptable meaning/usefulness ratings across held-out repeated outputs, with **no severe sense, negation, or grammatical misrepresentation** in the reviewed release set. Report per-direction results as well as aggregates; a small corpus is not proof of general correctness.
- Alignment failures preserve the natural message, examples, and existing speech behavior. Verify cancellation, language switching, late completion, restart, and legacy persistence. Verify long chunks and notes fit the current literal-view layout without reintroducing pager issues.
- On supported physical iPhones, record OS/model availability, expression length, cold/warm runs, time to natural translation, time to usable chunks, repair frequency, and p50/p95 end-to-end latency. Log synthetic evaluation text only; no collection of private learner input by default.
- Retain the two-call alignment ceiling. As an initial budget, target no more than a 20% p95 end-to-end latency increase over baseline on the same device/corpus; report any quality tradeoff and obtain a product decision before accepting a larger increase. Establish an absolute user-wait budget from measurements rather than inventing a device-independent guarantee.

Implementation order: corpus/baseline → context and rule experiments → structural checks and bounded failure handling → compatible model/UI/persistence integration → held-out and device verification. Keep prompt variants versioned for comparison and rollback. Deployment remains a separate authorized step.

## Expected implementation touchpoints

`Services/Messages/MessageGenerationPrompt.swift`, `Services/Messages/FoundationModelsMessageService.swift`, `Models/LearningMessage.swift`, `Models/MessageSessionRecord.swift`, and `Views/MessageCard.swift`. Staged delivery would additionally involve `Stores/MessageStore.swift` and queue coordination. Add localized availability/note labels to `Interface.xcstrings`. This plan changes none of those files.
