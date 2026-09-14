# The Chinese Room

The Chinese Room is an AI language learning iOS app. It allows users to learn any languages using any language from anywhere in a vibe-based fashion instead of a traditional structured systematic way of learning.

## Tech Stacks

- SwiftUI
- SwiftData
- Apple on-device Foundation Models with guided generation
- Apple Translation for whole-expression translation
- Apple Speech for on-device dictation
- AVSpeechSynthesizer for system text-to-speech

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
No bundled model or external Swift package is required. Validate quality and
latency on the target iPhone.

## Design

Main background color is light beige. Text is black.
