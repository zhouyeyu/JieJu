#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0-alpha}"
if [[ ! "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 2
fi

OUTPUT_DIR="$PROJECT_ROOT/artifacts/macos"
PACKAGE_DIR="$PROJECT_ROOT/artifacts/packages"
STAGE_DIR="$OUTPUT_DIR/JieJu-macOS-$VERSION"
ARCHIVE_NAME="JieJu-macOS-$VERSION.zip"
ARCHIVE_PATH="$PACKAGE_DIR/$ARCHIVE_NAME"

"$PROJECT_ROOT/scripts/build-macos.sh"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$PACKAGE_DIR"
ditto "$OUTPUT_DIR/JieJu.app" "$STAGE_DIR/JieJu.app"
cp "$PROJECT_ROOT/LICENSE" "$STAGE_DIR/LICENSE.txt"
cp "$PROJECT_ROOT/NOTICE" "$STAGE_DIR/NOTICE.txt"
COMMIT="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
cat > "$STAGE_DIR/PACKAGE-README.txt" <<EOF
JieJu macOS development preview $VERSION

Move JieJu.app to Applications and open it from Finder. macOS 14 or later is required.
Ollama is optional and is only needed for local AI explanations.

Build commit: $COMMIT
This is an unsigned development preview. Public releases must be Developer ID signed and notarized.
EOF

rm -f "$ARCHIVE_PATH" "$ARCHIVE_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR" "$ARCHIVE_PATH"
HASH="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$HASH" "$ARCHIVE_NAME" > "$ARCHIVE_PATH.sha256"
rm -rf "$STAGE_DIR"
echo "macOS package ready: $ARCHIVE_PATH"
echo "SHA-256: $HASH"
