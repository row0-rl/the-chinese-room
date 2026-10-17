#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/room-appearance.XXXXXX")"
SIMULATOR_ID="${SIMULATOR_ID:-booted}"
BUNDLE_ID="com.example.TheChineseRoom.AppearanceRegression"
cleanup() {
  xcrun simctl uninstall "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT
APP_PATH="$TEST_DIR/AppearanceRegression.app"
mkdir -p "$APP_PATH"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -sdk "$SDK_PATH" \
  -target "$(uname -m)-apple-ios27.0-simulator" \
  "$ROOT_DIR/TheChineseRoom/Support/Environment.swift" \
  "$ROOT_DIR/tests/AppearanceRegression.swift" -o "$APP_PATH/AppearanceRegression"
cat > "$APP_PATH/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.example.TheChineseRoom.AppearanceRegression</string>
  <key>CFBundleExecutable</key><string>AppearanceRegression</string>
  <key>CFBundleName</key><string>AppearanceRegression</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>MinimumOSVersion</key><string>27.0</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key><dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key><dict/>
  </dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP_PATH" >/dev/null 2>&1
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
for scenario in normal forced-light; do
  if [[ "$scenario" == "forced-light" ]]; then
    xcrun simctl launch --terminate-running-process --console "$SIMULATOR_ID" "$BUNDLE_ID" \
      -appAppearance light -appearanceRegressionSentinel untouched > "$TEST_DIR/output.log" 2>&1
  else
    xcrun simctl launch --terminate-running-process --console "$SIMULATOR_ID" "$BUNDLE_ID" > "$TEST_DIR/output.log" 2>&1
  fi
  cat "$TEST_DIR/output.log"
  rg -q '^PASS: appearance transitions,' "$TEST_DIR/output.log"
done
