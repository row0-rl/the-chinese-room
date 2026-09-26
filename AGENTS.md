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

Messages use four sequential stages: Apple Foundation Models generates or normalizes the original expression, Apple Translation translates it, Apple Foundation Models segments the target expression using delimiter-based text output in permissive transformation mode, and one Apple Foundation Models request glosses the validated fixed chunks. Segmentation has one correction attempt; gloss repair requests only missing or invalid chunk IDs while retaining valid glosses. Optional usage examples are currently omitted.

### Random Messages

On opening the app, the page shows a random message. User can swipe down to generate a next random message, and swipe up to go back to the previous message.

### User Sent Messages

On the bottom of the page is an input area with a hold-to-speak dictation button as the main input interface, and a keyboard to type option on the right. Text input from this input area becomes the expression for the next message.

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

Japanese Hepburn notation is generated lazily when the pronunciation button is
opened. The app preserves source spans using Apple's Japanese tokenizer, joining
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
