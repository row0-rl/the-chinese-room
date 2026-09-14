#!/usr/bin/env bash
set -euo pipefail

# Use the project’s Xcode 27 toolchain unless explicitly overridden.
if [[ -z "${DEVELOPER_DIR:-}" && -d "$HOME/Downloads/Xcode-beta.app" ]]; then
  export DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
fi

PROJECT="${PROJECT:-TheChineseRoom.xcodeproj}"
SCHEME="${SCHEME:-TheChineseRoom}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
TARGET="${TARGET:-simulator}"
DEVICE="${DEVICE:-}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DerivedData}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.example.TheChineseRoom}"
ATTACH_CONSOLE="${ATTACH_CONSOLE:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$PROJECT"
DERIVED_DATA_ABS="$ROOT_DIR/$DERIVED_DATA_PATH"

usage() {
  cat <<EOF
Usage:
  $0 [--target simulator|device] [options]

Options:
  --target simulator|device   Run on an iOS Simulator or a physical iPhone. Default: simulator
  --simulator NAME            Simulator name. Default: iPhone 17
  --device NAME_OR_ID         Physical device name, UDID, serial number, or DNS name
  --list-devices              Print devices known to devicectl
  --configuration NAME        Xcode configuration. Default: Debug
  --scheme NAME               Xcode scheme. Default: TheChineseRoom
  --project PATH              Xcode project. Default: TheChineseRoom.xcodeproj
  --derived-data PATH         DerivedData path. Default: build/DerivedData
  --bundle-id ID              App bundle identifier. Default: com.example.TheChineseRoom
  --no-console                Launch and exit instead of streaming app stdout/stderr
  -h, --help                  Show this help

Examples:
  $0
  $0 --target simulator --simulator "iPhone 17"
  $0 --target device --device "Rowan's iPhone"
  $0 --target device --device 00008110-001234567890801E
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --simulator)
      SIMULATOR_NAME="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --list-devices)
      xcrun devicectl list devices
      exit 0
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --project)
      PROJECT="$2"
      PROJECT_PATH="$ROOT_DIR/$PROJECT"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA_PATH="$2"
      DERIVED_DATA_ABS="$ROOT_DIR/$DERIVED_DATA_PATH"
      shift 2
      ;;
    --bundle-id)
      APP_BUNDLE_ID="$2"
      shift 2
      ;;
    --no-console)
      ATTACH_CONSOLE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Project not found: $PROJECT_PATH" >&2
  exit 1
fi

case "$TARGET" in
  simulator)
    DESTINATION="platform=iOS Simulator,name=$SIMULATOR_NAME"
    PRODUCT_PLATFORM="iphonesimulator"
    ;;
  device)
    if [[ -z "$DEVICE" ]]; then
      echo "Missing required --device for physical iPhone runs." >&2
      echo "Run '$0 --list-devices' and pass the device Name, identifier, UDID, serial, or DNS name." >&2
      exit 1
    fi
    DESTINATION="platform=iOS,name=$DEVICE"
    PRODUCT_PLATFORM="iphoneos"
    ;;
  *)
    echo "Invalid --target: $TARGET. Expected simulator or device." >&2
    exit 1
    ;;
esac

echo "Project: $PROJECT"
echo "Scheme: $SCHEME"
echo "Configuration: $CONFIGURATION"
echo "Destination: $DESTINATION"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -allowProvisioningUpdates \
  -derivedDataPath "$DERIVED_DATA_ABS" \
  build

APP_PATH="$DERIVED_DATA_ABS/Build/Products/$CONFIGURATION-$PRODUCT_PLATFORM/$SCHEME.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found: $APP_PATH" >&2
  exit 1
fi

case "$TARGET" in
  simulator)
    xcrun simctl boot "$SIMULATOR_NAME" 2>/dev/null || true
    xcrun simctl bootstatus "$SIMULATOR_NAME" -b
    open -a Simulator
    xcrun simctl install "$SIMULATOR_NAME" "$APP_PATH"
    echo "Launched $APP_BUNDLE_ID on simulator $SIMULATOR_NAME."
    if [[ "$ATTACH_CONSOLE" == "1" ]]; then
      echo "Streaming app logs. Press Ctrl-C to stop."
      xcrun simctl launch --terminate-running-process --console "$SIMULATOR_NAME" "$APP_BUNDLE_ID"
    else
      xcrun simctl launch --terminate-running-process "$SIMULATOR_NAME" "$APP_BUNDLE_ID"
    fi
    ;;
  device)
    xcrun devicectl device install app --device "$DEVICE" "$APP_PATH"
    echo "Launched $APP_BUNDLE_ID on device $DEVICE."
    if [[ "$ATTACH_CONSOLE" == "1" ]]; then
      echo "Streaming app logs. Press Ctrl-C to stop."
      xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --console "$APP_BUNDLE_ID"
    else
      xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$APP_BUNDLE_ID"
    fi
    ;;
esac
