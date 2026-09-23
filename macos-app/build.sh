#!/bin/bash
# 构建 ZVVQuest.app（不依赖 Xcode，只用 Command Line Tools）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ZVVQuest"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP="$DIST_DIR/$APP_NAME.app"
MODULE_CACHE="$BUILD_DIR/modulecache"

# 选择一个能用的 SDK。
# 新 SDK 把 SwiftUI 的 @State 等属性包装器改成了宏（实现在 SwiftUICore 里），
# 而 Command Line Tools 不带 SwiftUIMacros 插件（装了完整 Xcode 才有）。
# 这里直接拿编译器试编译一段带 @State 的代码，能用哪个 SDK 就用哪个：
# 先试默认 SDK，不行再按版本从新到旧找可用的。
SDK_CACHE="$BUILD_DIR/sdk-choice.txt"
pick_sdk() {
	if [ -n "${ZVV_SDK:-}" ]; then echo "$ZVV_SDK"; return; fi
	if [ -s "$SDK_CACHE" ] && [ -d "$(cat "$SDK_CACHE")" ]; then cat "$SDK_CACHE"; return; fi

	local probe_dir
	probe_dir="$(mktemp -d)"
	cat >"$probe_dir/probe.swift" <<'PROBE'
import SwiftUI
struct Probe: View {
    @State private var value = 0
    var body: some View { Text("\(value)") }
}
PROBE

	local chosen=""
	local default_sdk
	default_sdk="$(xcrun --sdk macosx --show-sdk-path)"
	local candidates=("$default_sdk")
	for candidate in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -Vr); do
		candidates+=("$candidate")
	done

	for candidate in "${candidates[@]}"; do
		local major
		major="$(basename "$candidate" | sed -e 's/^MacOSX//' -e 's/\.sdk$//' -e 's/\..*$//')"
		case "$major" in ''|*[!0-9]*) continue ;; esac
		if swiftc -sdk "$candidate" -target "arm64-apple-macos${major}.0" \
			-module-cache-path "$MODULE_CACHE/sdk$major" \
			-typecheck "$probe_dir/probe.swift" >/dev/null 2>&1; then
			chosen="$candidate"
			break
		fi
	done
	rm -rf "$probe_dir"

	if [ -z "$chosen" ]; then chosen="$default_sdk"; fi
	echo "$chosen" >"$SDK_CACHE"
	echo "$chosen"
}

SDK="$(pick_sdk)"
SDK_MAJOR="$(basename "$SDK" | sed -e 's/^MacOSX//' -e 's/\.sdk$//' -e 's/\..*$//')"
DEPLOY_TARGET="${ZVV_DEPLOY_TARGET:-arm64-apple-macos${SDK_MAJOR}.0}"

mkdir -p "$BUILD_DIR" "$DIST_DIR" "$MODULE_CACHE"

echo "==> 编译 Swift 源码（target ${DEPLOY_TARGET}）"
echo "    使用 SDK：$SDK"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find "$ROOT/Sources" -name '*.swift' | sort)

swiftc \
	-O \
	-parse-as-library \
	-sdk "$SDK" \
	-target "$DEPLOY_TARGET" \
	-module-cache-path "$MODULE_CACHE" \
	-o "$BUILD_DIR/$APP_NAME" \
	"${SOURCES[@]}"

echo "==> 组装 App Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
# 最低系统版本跟随实际使用的 SDK
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion ${SDK_MAJOR}.0" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
	cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# 内置素材库：优先用环境变量指定的目录，否则自动往上找 vv
LIBRARY_SOURCE="${ZVV_LIBRARY:-}"
if [ -z "$LIBRARY_SOURCE" ]; then
	for candidate in "$ROOT/vv" "$ROOT/../vv" "$ROOT/../../vv" "$ROOT/../../../vv"; do
		if [ -d "$candidate" ]; then
			LIBRARY_SOURCE="$candidate"
			break
		fi
	done
fi
if [ -n "$LIBRARY_SOURCE" ] && [ -d "$LIBRARY_SOURCE" ]; then
	echo "==> 内置素材库：$LIBRARY_SOURCE"
	mkdir -p "$APP/Contents/Resources/vv"
	rsync -a --exclude '.DS_Store' "$LIBRARY_SOURCE/" "$APP/Contents/Resources/vv/"
else
	echo "==> 未找到 vv 素材目录，App 会在运行时自动查找（可在设置里手动指定）"
fi

# 内置云端 skill 提示词，和 Codex 插件共用同一份
SKILL_PROMPT="$ROOT/../xcode-tools/skills/zvv-meme/prompt.md"
if [ -f "$SKILL_PROMPT" ]; then
	mkdir -p "$APP/Contents/Resources/skill"
	cp "$SKILL_PROMPT" "$APP/Contents/Resources/skill/prompt.md"
fi

echo "==> 临时签名"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "（签名跳过，不影响本机运行）"

echo "==> 完成：$APP"
du -sh "$APP" | awk '{print "    体积：" $1}'
