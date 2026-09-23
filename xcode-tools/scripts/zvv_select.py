#!/usr/bin/env python3
"""按语义从 vv 素材库里挑候选台词。

用法：
    python3 scripts/zvv_select.py "美国人的生活水平其实没那么好" --top 24
    python3 scripts/zvv_select.py "…" --json

输出的是“候选”，最终顺序请由模型按语义决定（见 skills/zvv-meme/SKILL.md）。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import zvv_common as common  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="ZVV 素材候选打分")
    parser.add_argument("query", help="用户的一句话")
    parser.add_argument("--top", type=int, default=24, help="返回条数（默认 24）")
    parser.add_argument("--library", help="素材目录（默认自动查找 vv）")
    parser.add_argument("--include-templates", action="store_true", help="包含空白 / 万能模板素材")
    parser.add_argument("--json", action="store_true", help="以 json 输出")
    args = parser.parse_args()

    directory = common.find_library(args.library)
    items = common.load_items(directory, include_templates=args.include_templates)
    if not items:
        print("素材库为空", file=sys.stderr)
        return 1

    ranked = common.rank(args.query, items, top=max(1, args.top))
    if args.json:
        print(json.dumps(
            {
                "query": args.query,
                "library": str(directory),
                "total": len(items),
                "name": common.semantic_name(args.query, ranked[0]["title"] if ranked else None),
                "candidates": ranked,
            },
            ensure_ascii=False,
            indent=2,
        ))
        return 0

    print(f"素材库：{directory}（{len(items)} 张可用）")
    print(f"句子：{args.query}")
    print(f"建议文件名：{common.semantic_name(args.query, ranked[0]['title'] if ranked else None)}")
    for index, candidate in enumerate(ranked, start=1):
        topics = "/".join(candidate["topics"]) or "-"
        print(f"{index:2d}. {candidate['score']:.3f}  [{topics}] {candidate['title']}  ({Path(candidate['file']).name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
