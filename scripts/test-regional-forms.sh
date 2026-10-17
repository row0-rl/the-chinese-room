#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-regional.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc -target "$(uname -m)-apple-macos27.0" \
  tests/Support/AppAppearanceStub.swift \
  TheChineseRoom/Models/{LearningMessage,LanguageVariations}.swift \
  TheChineseRoom/Services/Messages/{AppleMessageRuntime,GeneratedLanguageCheck,MessageGenerationPrompt}.swift \
  tests/RegionalFormsSmoke.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
