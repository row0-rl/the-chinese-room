#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-lifecycle.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc -target "$(uname -m)-apple-macos26.0" \
  TheChineseRoom/Models/{LearningMessage,MessageSessionRecord}.swift \
  TheChineseRoom/App/AppConfiguration.swift \
  TheChineseRoom/Services/Messages/{MessageService,MockMessageService,AppleTranslationService}.swift \
  TheChineseRoom/Services/Speech/SpeechService.swift \
  TheChineseRoom/Services/Dictation/DictationService.swift \
  TheChineseRoom/Stores/{MessageStore,MessageQueueActor}.swift \
  tests/MessageLifecycleRegression.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
