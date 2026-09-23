#!/bin/bash
# 生成 Resources/AppIcon.icns
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ICONSET="$BUILD/AppIcon.iconset"

mkdir -p "$BUILD" "$ROOT/Resources" "$ICONSET"
swiftc -O -module-cache-path "$BUILD/modulecache" "$ROOT/tools/make-icon.swift" -o "$BUILD/make-icon"
"$BUILD/make-icon" "$ICONSET" "$ROOT/Resources/AppIcon.icns"
if iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns" 2>/dev/null; then
	echo "（iconutil 校验通过，已用系统工具重新打包）"
fi
echo "已生成 $ROOT/Resources/AppIcon.icns"
