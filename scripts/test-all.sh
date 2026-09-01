#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_PATH="$PROJECT_ROOT/TestResults/JieJu.xcresult"

swift test --package-path "$PROJECT_ROOT/Packages/JieJuLanguage"

mkdir -p "$PROJECT_ROOT/TestResults"
if [[ -e "$RESULTS_PATH" ]]; then
    rm -rf "$RESULTS_PATH"
fi

xcodebuild test \
    -project "$PROJECT_ROOT/JieJu.xcodeproj" \
    -scheme JieJu \
    -destination 'platform=macOS' \
    -resultBundlePath "$RESULTS_PATH"
