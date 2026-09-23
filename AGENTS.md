# The Chinese Room

The Chinese Room is an AI language learning iOS app. It allows users to learn any languages using any language from anywhere in a vibe-based fashion instead of a traditional structured systematic way of learning.

## Tech Stacks

- SwiftUI
- SwiftData
- Apple Foundation Models with guided generation; Private Cloud Compute for contextual Japanese readings with an on-device fallback
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
opened. The model returns exact source spans and contextual katakana readings;
the app validates and persists them, then converts katakana to Hepburn locally.
Private Cloud Compute requires Apple's managed
`com.apple.developer.private-cloud-compute` entitlement. The project must remain
signable without that entitlement and fall back to the on-device system model.
After Apple grants the entitlement, add it to the signing profile and define the
`PRIVATE_CLOUD_COMPUTE` Swift compilation condition to enable the PCC path.

## Design

Main background color is light beige. Text is black.
