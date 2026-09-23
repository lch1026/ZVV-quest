#!/bin/bash
# 构建并运行
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.sh"
open "$ROOT/dist/ZVVQuest.app"
