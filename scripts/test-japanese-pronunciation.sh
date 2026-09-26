#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-japanese-check.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc -DDEBUG -target "$(uname -m)-apple-macos27.0" \
  TheChineseRoom/Models/LearningMessage.swift \
  TheChineseRoom/Services/Pronunciation/{AppleJapanesePronunciationService,JapaneseRomajiNotation,KoreanRevisedRomanization,ApplePinyinNotation,IPANotation}.swift \
  tests/JapanesePronunciationSmoke.swift -o "$TEST_DIR/check"
"$TEST_DIR/check" "$@"
