#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/artifacts/macos}"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"

mkdir -p "$OUTPUT_DIR"
xcodebuild \
  -project "$PROJECT_ROOT/JieJu.xcodeproj" \
  -scheme JieJu \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

SOURCE_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/JieJu.app"
OUTPUT_APP="$OUTPUT_DIR/JieJu.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Build completed without JieJu.app: $SOURCE_APP" >&2
  exit 1
fi

rm -rf "$OUTPUT_APP"
ditto "$SOURCE_APP" "$OUTPUT_APP"
echo "macOS build ready: $OUTPUT_APP"
