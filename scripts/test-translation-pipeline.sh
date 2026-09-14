#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-translation.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc -target "$(uname -m)-apple-macos26.0" \
  TheChineseRoom/Models/LearningMessage.swift \
  TheChineseRoom/Services/Messages/{MessageService,AppleTranslationService,GeneratedMessage,GeneratedLanguageCheck,MessageGenerationPrompt,FoundationModelsMessageService}.swift \
  tests/TranslationPipelineRegression.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
