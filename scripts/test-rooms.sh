#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-tabs.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc -target "$(uname -m)-apple-macos26.0" \
  tests/Support/AppAppearanceStub.swift \
  TheChineseRoom/Models/{LearningMessage,MessageSessionRecord,RoomRecord,LanguageVariations,SavedMessageCollection}.swift \
  TheChineseRoom/App/AppConfiguration.swift \
  TheChineseRoom/Services/Messages/{MessageService,MockMessageService,AppleTranslationService}.swift \
  TheChineseRoom/Services/Speech/SpeechService.swift \
  TheChineseRoom/Services/Dictation/DictationService.swift \
  TheChineseRoom/Stores/{MessageStore,MessageQueueActor,RoomStore}.swift \
  tests/RoomsRegression.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
