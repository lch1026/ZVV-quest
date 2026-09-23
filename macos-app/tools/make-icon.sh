#!/bin/bash
# 生成 Resources/AppIcon.icns
# 优先用 Resources/AppIcon.png（项目自带图标）；没有时才回退到 tools/make-icon.swift 生成的默认图标。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ICONSET="$BUILD/AppIcon.iconset"
SOURCE_PNG="$ROOT/Resources/AppIcon.png"

mkdir -p "$BUILD" "$ROOT/Resources"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

if [ -f "$SOURCE_PNG" ]; then
	echo "==> 用 $SOURCE_PNG 生成图标"
	for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
		"128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
		"512 icon_512x512" "1024 icon_512x512@2x"; do
		size="${spec%% *}"
		name="${spec##* }"
		sips -s format png -z "$size" "$size" "$SOURCE_PNG" --out "$ICONSET/$name.png" >/dev/null
	done
else
	echo "==> 未找到 Resources/AppIcon.png，回退到内置图标生成器"
	swiftc -O -module-cache-path "$BUILD/modulecache" "$ROOT/tools/make-icon.swift" -o "$BUILD/make-icon"
	"$BUILD/make-icon" "$ICONSET" "$ROOT/Resources/AppIcon.icns"
fi

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "已生成 $ROOT/Resources/AppIcon.icns"
