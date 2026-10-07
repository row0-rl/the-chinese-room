# Generated-language regression checks

Run `bash scripts/test-generated-language.sh` on macOS 26+ with Xcode 26+.

The script compiles the production prompts, generated response types, validators,
repair policy, and starter-message code. It uses Apple's local Natural Language
recognizer and synthetic responses; it does **not** call Foundation Models or
establish real generation quality.

Covered cases include the reported Chinese → Korean screenshot's English source
heading and Korean predicate in a Chinese source example; English target examples
and literal glosses; empty glosses; legitimate names, acronyms, numbers, shared Han
characters, and learner-quoted foreign content; one-attempt success, repaired
success, and a two-attempt invalid-result ceiling.

The malformed Chinese example and its mismatched Korean meaning are retained as
an explicit limitation: passing a language check does not validate grammar or
meaning. The checker intentionally uses conservative signals, not a script ban;
unrecognized English vocabulary and Korean forms may still escape it. Actual
quality and false-positive rates need reviewed on-device generation runs.

Existing saved cards are not rewritten. New starter cards follow the selected
language pair, so unrelated English/French sample text no longer seeds a fresh
Chinese/Korean session.

## On-device generation

`bash scripts/test-afm-generation.sh` exercises the production AFM runtime with
separate guided segmentation and gloss requests on this Mac against fixed French
and Korean sentences. It requires Apple Intelligence
to be enabled and ready. It does not download models or test iPhone performance.
See [generation setup](../docs/generation.md).

## Message lifecycle

Run `bash scripts/test-message-lifecycle.sh` to exercise the production store
and queue with a controlled service. It covers delayed reset protection, busy
submission, foreground cancellation recovery, explicit swipe retry, and the
absence of automatic restart after canceled startup prefetch. No model is loaded.

## Four-stage pipeline

Run bash scripts/test-translation-pipeline.sh to check source → Apple translation →
segmentation → glossing, formatting restoration, and the segmentation gate.
It covers segmentation repair with previous output, missing and duplicate gloss
IDs, out-of-order results, targeted repairs that preserve good glosses, model
failure isolation, cancellation propagation, and translation queue cancellation.
The app’s SwiftUI host handles translation download consent.

Pinyin pronunciation and chunk alignment:

```sh
bash scripts/test-pinyin-notation.sh
```

Checks full-expression Apple transliteration, chunk coverage, mixed Latin text,
punctuation normalization, and safe failure for unconverted characters. These
checks verify alignment; Apple can still choose an incorrect reading for a
polyphonic character (for example, 行 in 银行).

Live on-device Japanese pronunciation (requires macOS 27 and an available
Apple Intelligence model):

```sh
bash scripts/test-japanese-pronunciation.sh
```

Runs 14 sentences through reading generation and the actual Hepburn layout.
Fails on missing results, changed source text, invalid katakana, or Japanese
spans without romanization. Covers compounds, particles, inflected verbs,
counters, punctuation, whitespace, and emoji. Prints full readings and reports
linguistic mismatches separately; `--strict-quality` makes those mismatches fail
the run too. The default functional pass does not establish pronunciation
accuracy or on-iPhone performance.

Live on-device IPA generation (macOS 27 with an available Apple Intelligence model):

```sh
bash scripts/test-ipa-pronunciation.sh
```

Checks source preservation and nonempty IPA display for a sentence in each of the
eight IPA languages. Prints generated readings and selected-word reference
comparisons separately; a functional pass is not a pronunciation-quality pass.
Some languages can return transformations despite not being advertised by
`supportsLocale`; failures are handled as unavailable and can be retried.
`test-pinyin-notation.sh` also checks IPA diacritics, formatting, Unicode offsets,
and rejection of mismatched source annotations. `test-message-lifecycle.sh` covers
IPA request deduplication, failure/retry, caching, persistence, and legacy records.

## Hanja annotations

`bash scripts/test-message-lifecycle.sh` checks Hanja alignment, repeated spans,
particle preservation, Unicode offsets, automatic startup and prefetch requests, request deduplication, retry, empty
result caching, persistence, legacy records, and language-mode isolation.

`bash scripts/test-hanja-generation.sh` runs 14 fixed Korean sentences through
real on-device Foundation Models on the Mac. It requires an available system
model and exits nonzero if any result misses the sample expectations. This is
an explicit quality check, not a mocked generation test. See
`HanjaGenerationResults.md` for the latest observed results and limitations.

## Dictation startup

Lifecycle regression coverage includes release during asynchronous startup,
duplicate start events, stale completion after a new press, and cancellation
before the startup task executes. The recording UI becomes ready only after
`startRecording` returns; permission dialogs do not count as active recording.
The live message card appears during startup, displays partial transcripts while
holding, and keeps its ID through final transcription and generation. Empty or
canceled recordings and failed startup remove the draft; late callbacks and
canceled generation cannot restore it.

The Debug launch argument `--dictation-smoke-test` performs three brief microphone
startup/cancellation checks on a physical iPhone. It requires previously granted
speech and microphone access, saves no recording, and does not assess transcription
accuracy. On Cobble (iPhone 17 Pro), the 2026-09-28 run measured 0.179s, 0.155s,
and 0.160s to engine readiness. All three cancellations left the engine stopped
and the tap removed. These are post-change measurements, not a before/after comparison.

The 2026-09-29 dictation executor check uses a dedicated dispatch serial executor
for microphone and recognition lifecycle operations. Startup asserts it is not
on the main thread. During three physical iPhone startups (0.184s, 0.160s,
0.162s), a main-actor task scheduled every 10ms ran 16, 14, and 14 times.
All cancellations stopped capture and removed the tap. This verifies main-actor
availability during audio setup; it does not measure touch-to-first-red-frame
latency or live transcription quality.

The microphone press uses a native UIControl with begin/end/cancel tracking.
Its red layer and icon are updated directly before dispatching app work, avoiding
the former SwiftUI drag gesture and view-state redraw dependency. Dragging outside
the control cancels, as do backgrounding and view removal; VoiceOver activation
toggles the recording hold. Debug `[Dictation touch]` logs report event delivery
age and delay until startup dispatch. These logs do not measure pixels appearing
on screen. Actual finger-to-red latency still requires a physical interaction check.
