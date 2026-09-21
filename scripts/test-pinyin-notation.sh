#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-pinyin-check.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc \
  TheChineseRoom/Models/LearningMessage.swift \
  TheChineseRoom/Services/Pronunciation/ApplePinyinNotation.swift \
  tests/PinyinNotationRegression.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
