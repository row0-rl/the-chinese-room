# The Chinese Room

The Chinese Room is an AI language learning iOS app. It allows users to learn any languages using any language from anywhere in a vibe-based fashion instead of a traditional structured systematic way of learning.

## Tech Stacks

- SwiftUI
- SwiftData
- Apple Foundation Models with guided generation; on-device text transformation for Japanese readings
- Apple Translation for whole-expression translation
- Apple Speech for on-device dictation
- Supertonic 3 via FluidAudio/Core ML for English, French, Korean, Spanish, Portuguese, Italian, Japanese, Russian, Hindi and Swedish text-to-speech; Apple system speech for Mandarin

## Features

The app's core logic centers around **messages**.

A message contains:

- (Normalized) input expression in original language. e.g. "I am hungry."
- Translated expression in target language. e.g. "J’ai faim."
- Literal meaning of the expression. e.g. "I have hunger."
- Press to listen to target language powered by a TTS model.
- Example usage/sentences of the expression in both languages.

Messages normally use four sequential stages: Apple Foundation Models generates or normalizes the original expression, Apple Translation translates it, Apple Foundation Models segments the target expression using delimiter-based text output in permissive transformation mode, and one Apple Foundation Models request glosses the validated fixed chunks. Target forms outside the translation baselines add a bounded on-device regional transformation before segmentation; this also applies to the Mexican Spanish picker default. Mandarin–Cantonese pairs use this transformation directly because Apple Translation rejects them as the same base language. Cantonese uses a Chinese writing model with explicit instructions; dialect accuracy is experimental. Chinese writing systems are normalized locally. Segmentation has one correction attempt; gloss repair requests only missing or invalid chunk IDs while retaining valid glosses. Optional usage examples are currently omitted.

### Rooms

Users create saved Rooms, each representing one directional language pair.
Room selection and management live exclusively in Settings › Rooms. Selecting a
Room restores its message history and last viewed card. Add a room creates a
Room; adding an existing pair opens that Room, including archived Rooms.
Each side chooses a language and an Origin / form. Every language has multiple
regional forms; Chinese includes Mandarin and Cantonese with explicit writing
systems. New rooms and language changes prefer US English, France French, mainland
Mandarin in Simplified Chinese, standard South Korean, Mexican Spanish, Brazilian
Portuguese, Italy Italian, standard Japanese, Russia Russian, standard Hindi, and
Sweden Swedish. New rooms do not automatically advance to an unused region.
Mandarin–Cantonese pairs use Hong Kong Cantonese on the Cantonese side to keep the
spoken languages distinct. Explicit choices in existing rooms remain intact. Room labels and IDs include the selected forms, with independent history
for each pair. Legacy form IDs remain unchanged. The pickers exclude the opposite
spoken language; two regional forms of the same language cannot form a Room.
Mandarin and Cantonese have distinct spoken-language identities.
Long-press a Room to pin, rename, or archive it. Archived Rooms can be restored
from the same settings screen. The main screen has only the Settings gear.
Pinned Rooms come first; other Rooms use a snapshot of recent use at launch and
stay in place during a session. Custom names always retain the language-pair label.
Room metadata and per-pair message sessions are stored separately in SwiftData.
Existing saved sessions and the previously selected pair become Rooms on upgrade.
Archiving hides a Room without deleting its messages. Archiving every Room returns
to a create-or-restore screen. Cross-launch message history is enabled.

### Saved messages

Tap a message sheet’s top-right corner to toggle saving immediately.
Drag that corner down-left to save the expression, or
up-right to unsave. The fold follows the finger and settles to the nearest state
on release; corner drags do not page the feed. The saved fold rests at 64 points,
can stretch to 160 points while dragging, and springs back to its resting size
on release. A cylindrical surface model bends the corner without stretching
its paper coordinates. The tip target follows diagonal progress and the finger's
movement along the curl; changing that target rotates the curl axis, so both
joins come from the same surface rather than independent edge offsets.
The front, yellow backside, silhouette and pencil contours are projected
from that surface. The entire border is a single projected pencil stroke while
curled, so the joins have no independently clipped stroke ends. Pencil textures
are prepared once in flat paper coordinates and projected in Canvas with the
current curl pose; dragging never waits for a newly rasterized outline. The
canvas covers the full projected paper bounds, including overflow beyond short
cards. Front ink, opaque backside fill, and back ink render in depth order so
the original bottom border cannot show through the lifted paper. The lifted
corner has no cast shadow or surface-darkening gradient. The diagonal curl
silhouette has a separate thin 0.8-point pencil outline (the sheet border uses
3.3 points). Unsaved sheets have a completely flat corner. Saving gives
a light haptic. This is a geometric page-curl approximation, not a material
physics simulation. Message text and notebook rules stay visible through the
front of the bend and are clipped at the projected silhouette, not the bend's
starting axis; their positions are not yet warped across the curved surface.
VoiceOver exposes a save/unsave action. The first-use hint disappears after saving. Reduce Motion uses a short
transition. Save state is stored with the message in its Room history; legacy
messages default to unsaved. Saved collections and feed resurfacing are not yet
implemented.

### Random Messages

On opening the app, the page shows a random message. User can swipe down to generate a next random message, and swipe up to go back to the previous message.

### User Sent Messages

On the bottom of the page is an input area with a hold-to-speak dictation button as the main input interface, and a keyboard to type option on the right. Text input from this input area becomes the expression for the next message.

In typing mode, swiping down over the message area or typing bar dismisses the
keyboard and returns to dictation controls without clearing the typed draft.

Input text should be normalized. For example, "Me be hungry" likely means "I am hungry".

## Device Requirements

The project targets iOS 27 and builds with Xcode 27. Message generation requires
Apple Intelligence to be available and enabled, its system model downloaded, and
both selected languages supported. Translation requires the corresponding Apple
Translation language assets, with downloads handled by the app's translation task.
Speech uses the pinned FluidAudio Swift package. English, French, Korean,
Spanish, Portuguese, Italian, Japanese, Russian, Hindi and Swedish use the shared Supertonic 3
INT4 Core ML model; Mandarin uses the installed Apple system speech voices.
Supertonic assets download on first use and are cached for offline playback. No model setup script is required before
building. See `docs/speech.md` for runtime limits and
third-party notices. Validate quality, stability and latency on the target iPhone.

Japanese Hepburn notation is generated automatically when a message is prepared. The app preserves source spans using Apple's Japanese tokenizer, joining
adjacent kanji and chunks ending in small tsu with their following syllable.
The on-device Foundation Models service converts each kanji-containing span to
kana with the full sentence as context, using plain-text permissive transformation
mode. Kana-only spans are converted locally. Hiragana model output is normalized
to katakana before validation and persistence; Hepburn conversion remains local.
PCC is not used. Linguistic accuracy is still experimental; the live pronunciation
smoke test checks rendering independently and reports reading-quality mismatches.

IPA for English, French, Spanish, Portuguese, Italian, Russian, Hindi, and Swedish
is generated lazily on-device when pronunciation is opened. The app fixes word
spans locally, supplies the sentence and target locale to a plain-text Foundation
Models transformation, normalizes IPA formatting, and persists the readings with
the message. Model availability is required; successful output does not establish
linguistic accuracy or official locale support. IPA accuracy remains experimental.

## Design

Main background color is light beige. Text is black.

Settings › Appearance chooses System, Light or Dark (stored in `UserDefaults`). Dark uses a warm charcoal palette: background
`#1F1813`, cream ink `#F0E2CA`, card fill `#2D241C`, and amber notebook rules.
All app colors come from the adaptive palette in `Support/Environment.swift`.
Appearance applies to the hosting window so the main screen and open sheets
update together. System clears the window override. Preview launch appearance
options seed the preference once and cannot override later picker changes.
PencilKit text, borders and rules render black or yellow and are tinted for the current appearance when drawn.

### Hanja annotations

For Chinese speakers learning Korean, preparing a message starts a separate,
on-device Foundation Models request. The AI transforms only Sino-Korean spans
into Hanja; local validation requires an exact character correspondence and
preserves particles, spacing, and punctuation. The app stores UTF-16 source
offsets and caches successful results, including empty results, with each message.
Failed requests can be retried by hiding and showing annotations. No dictionary
is used. Structural validation cannot verify etymological correctness; see
`tests/HanjaGenerationResults.md` for live model limitations.

Pronunciation and Hanja requests start automatically for loaded history, newly generated messages, and prefetched cards. Tapping only reveals cached results or retries failures.

Sentence-ending full stops are removed locally before translation/segmentation and when restoring cards. Questions, exclamations, ellipses, initials, dotted abbreviations, and common abbreviated titles are preserved. Abbreviation detection is conservative and heuristic.

Dictation has a main-actor UI adapter and a worker actor backed by an explicit
serial DispatchQueue executor. Audio-session configuration, engine lifecycle,
and recognition callbacks run on the worker; only transcript/status delivery
returns to the main actor. Button press color follows touch state independently.
