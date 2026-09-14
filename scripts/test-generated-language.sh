#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-language-check.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc -target "$(uname -m)-apple-macos26.0" \
  TheChineseRoom/Models/LearningMessage.swift \
  TheChineseRoom/Services/Messages/MessageService.swift \
  TheChineseRoom/Services/Messages/MockMessageService.swift \
  TheChineseRoom/Services/Messages/GeneratedLanguageCheck.swift \
  TheChineseRoom/Services/Messages/MessageGenerationPrompt.swift \
  TheChineseRoom/Services/Messages/GeneratedMessage.swift \
  tests/GeneratedLanguageRegression.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
