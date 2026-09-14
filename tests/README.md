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
