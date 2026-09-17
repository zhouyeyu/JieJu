#!/bin/bash
set -euo pipefail

release_root="$(cd "$(dirname "$0")/.." && pwd)"
release_version="${1:-0.0.1}"
release_app="$release_root/build/macos-v$release_version/Build/Products/Release/JieJu.app"
release_output="$release_root/build/releases"
release_image="$release_output/JieJu-$release_version-macOS-arm64.dmg"
[[ -d "$release_app" ]] || { echo "Missing Release app: $release_app" >&2; exit 1; }
[[ ! -e "$release_image" ]] || { echo "Refusing to overwrite: $release_image" >&2; exit 1; }
release_stage="$(mktemp -d "${TMPDIR:-/tmp}/jieju-dmg.XXXXXX")"
trap 'rm -rf "$release_stage"' EXIT
mkdir -p "$release_output"
ditto "$release_app" "$release_stage/JieJu.app"
cp "$release_root/LICENSE" "$release_stage/LICENSE"
cp "$release_root/NOTICE" "$release_stage/NOTICE"
cp "$release_root/Docs/RELEASE-v$release_version.md" "$release_stage/README.md"
ln -s /Applications "$release_stage/Applications"
hdiutil create -volname "JieJu $release_version" -srcfolder "$release_stage" -format UDZO "$release_image"
hdiutil verify "$release_image"
(cd "$release_output" && shasum -a 256 "$(basename "$release_image")" > "$(basename "$release_image").sha256")
echo "$release_image"
