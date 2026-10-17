#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/paper-corner.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
xcrun swiftc -target "$(uname -m)-apple-macos26.0" \
  TheChineseRoom/Support/PaperCornerInteraction.swift \
  tests/PaperCornerInteractionRegression.swift -o "$TEST_DIR/check"
"$TEST_DIR/check"
