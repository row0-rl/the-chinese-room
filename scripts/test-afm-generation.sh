#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d "$HOME/Downloads/Xcode-beta.app" ]]; then
  export DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
fi
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-afm.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc -DDEBUG -target "$(uname -m)-apple-macos27.0" \
  TheChineseRoom/Models/LearningMessage.swift \
  TheChineseRoom/Services/Messages/{AppleMessageRuntime,AppleTranslationService,MessageService,FoundationModelsMessageService,GeneratedMessage,GeneratedLanguageCheck,MessageGenerationPrompt}.swift \
  tests/AFMGenerationSmoke.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
