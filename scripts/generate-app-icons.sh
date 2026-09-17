#!/bin/bash
# Package the approved artwork without changing its design. Requires macOS + Node.
set -euo pipefail
icon_project_root="$(cd "$(dirname "$0")/.." && pwd)"
icon_work_dir="$(mktemp -d -t jieju-icons)"
trap 'rm -rf "$icon_work_dir"' EXIT
icon_source="$icon_project_root/Shared/Brand/jieju-icon.png"
mkdir -p "$icon_work_dir/AppIcon.iconset" "$icon_work_dir/windows"
mkdir -p "$icon_project_root/JieJu/Resources" "$icon_project_root/Apps/Windows/JieJu.Windows/Assets"
for icon_size in 16 32 128 256 512; do
    sips -z "$icon_size" "$icon_size" "$icon_source" --out "$icon_work_dir/AppIcon.iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
    icon_retina_size=$((icon_size * 2))
    sips -z "$icon_retina_size" "$icon_retina_size" "$icon_source" --out "$icon_work_dir/AppIcon.iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_work_dir/AppIcon.iconset" -o "$icon_project_root/JieJu/Resources/AppIcon.icns"
for icon_size in 16 24 32 48 64 128 256; do
    sips -z "$icon_size" "$icon_size" "$icon_source" --out "$icon_work_dir/windows/${icon_size}.png" >/dev/null
done
node "$icon_project_root/scripts/package-windows-icon.mjs" "$icon_work_dir/windows" "$icon_project_root/Apps/Windows/JieJu.Windows/Assets/AppIcon.ico"
echo "Generated macOS ICNS and Windows ICO from Shared/Brand/jieju-icon.png"
