#!/usr/bin/env python3
"""把若干张张维为（ZVV）素材拼接成一张连续对话表情包 PNG。

两种模式：
    subtitle  台词拼接：裁切每张图的中部画面，压成字幕条（默认，参考“台词拼接实例”）
    full      整图竖向拼接：每张图等比缩放后自上而下拼起来

渲染优先级：
    1. 调 macos-app 编译出的 App 二进制（和 GUI 完全一致的渲染结果）
    2. 回退 Pillow（需要 pip install -r requirements.txt）

用法：
    python3 scripts/zvv_stitch.py "句子" --files "a.png,b.png" --mode subtitle --out /tmp/zvv.png
    python3 scripts/zvv_stitch.py "句子" --count 6 --json
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import zvv_common as common  # noqa: E402

MAX_IMAGES = 15
FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
]


def find_app_binary() -> Path | None:
    candidates: list[Path] = []
    if os.environ.get("ZVV_APP"):
        candidates.append(Path(os.environ["ZVV_APP"]).expanduser())
    repo = Path(__file__).resolve().parents[2]
    candidates.append(repo / "macos-app/dist/ZVVQuest.app/Contents/MacOS/ZVVQuest")
    candidates.append(Path.home() / "Applications/ZVVQuest.app/Contents/MacOS/ZVVQuest")
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def default_output(name: str) -> Path:
    cache = Path.home() / "Library/Caches/ZVVQuest"
    try:
        cache.mkdir(parents=True, exist_ok=True)
    except OSError:
        cache = Path("/tmp")
    return cache / f"ZVV-{name}.png"


def resolve_files(spec: str, directory: Path) -> list[Path]:
    result: list[Path] = []
    for raw in spec.split(","):
        token = raw.strip()
        if not token:
            continue
        candidate = Path(token).expanduser()
        if not candidate.is_absolute():
            candidate = directory / token
        if not candidate.is_file():
            candidate = Path(token).expanduser()
        if candidate.is_file():
            result.append(candidate)
    return result


def run_app(binary: Path, args: argparse.Namespace, files: list[Path], output: Path) -> dict:
    command = [
        str(binary),
        "--generate", args.query,
        "--mode", args.mode,
        "--count", str(args.count),
        "--width", str(args.width),
        "--out", str(output),
        "--json",
    ]
    if files:
        command += ["--files", ",".join(str(path) for path in files)]
    if args.library:
        command += ["--library", args.library]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0 or not output.is_file():
        raise RuntimeError(completed.stderr.strip() or "App 渲染失败")
    payload = json.loads(completed.stdout)
    payload["renderer"] = "macos-app"
    return payload


# MARK: - Pillow 回退实现

def load_font(size: int):
    from PIL import ImageFont

    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def draw_centered(draw, text: str, font, canvas_width: int, bottom_y: int, stroke: int = 4) -> None:
    from PIL import ImageDraw  # noqa: F401

    bbox = draw.textbbox((0, 0), text, font=font, stroke_width=stroke)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    x = (canvas_width - width) / 2 - bbox[0]
    y = bottom_y - height - bbox[1]
    draw.text((x, y), text, font=font, fill=(255, 255, 255), stroke_width=stroke, stroke_fill=(0, 0, 0))


def render_with_pillow(query: str, files: list[Path], lines: list[str], mode: str, width: int, gap: int, output: Path, name: str) -> dict:
    try:
        from PIL import Image
    except ImportError as error:  # pragma: no cover
        raise SystemExit(
            "需要 Pillow 才能在没有 App 的环境下渲染：\n"
            "  python3 -m pip install -r xcode-tools/requirements.txt\n"
            f"（原始错误：{error}）"
        )

    images = [Image.open(path).convert("RGB") for path in files]
    if mode == "full":
        scaled = []
        for image in images:
            height = max(1, round(width * image.height / image.width))
            scaled.append(image.resize((width, height), Image.LANCZOS))
        total_height = sum(image.height for image in scaled) + gap * (len(scaled) - 1)
        canvas = Image.new("RGB", (width, total_height), (15, 15, 18))
        offset = 0
        for image in scaled:
            canvas.paste(image, (0, offset))
            offset += image.height + gap
    else:
        bands = []
        for image in images:
            crop_height = max(1, int(image.height * 0.60))
            top = min(image.height - crop_height, int(image.height * 0.06))
            cropped = image.crop((0, top, image.width, top + crop_height))
            height = max(1, round(width * cropped.height / cropped.width))
            bands.append(cropped.resize((width, height), Image.LANCZOS))
        separator, footer_height = 6, 56
        total_height = sum(band.height for band in bands) + separator * (len(bands) - 1) + footer_height
        canvas = Image.new("RGB", (width, total_height), (0, 0, 0))
        from PIL import ImageDraw

        draw = ImageDraw.Draw(canvas)
        offset = 0
        font_size = max(16, int(width * 0.048))
        font = load_font(font_size)
        footer_font = load_font(max(12, int(width * 0.026)))
        for index, band in enumerate(bands):
            canvas.paste(band, (0, offset))
            # 底部压暗，保证字幕可读（RGB 画布上必须用 mask 合成，直接画带 alpha 的颜色会被忽略）
            shade_height = max(1, int(band.height * 0.45))
            mask = Image.new("L", (1, shade_height))
            for step in range(shade_height):
                mask.putpixel((0, step), int(205 * (step / max(1, shade_height - 1)) ** 1.7))
            mask = mask.resize((width, shade_height))
            shade_top = offset + band.height - shade_height
            region = canvas.crop((0, shade_top, width, offset + band.height))
            canvas.paste(Image.composite(Image.new("RGB", region.size, (0, 0, 0)), region, mask), (0, shade_top))
            draw_centered(draw, lines[index], font, width, offset + band.height - int(band.height * 0.12))
            offset += band.height
            if index < len(bands) - 1:
                draw.rectangle([0, offset, width, offset + separator], fill=(26, 26, 26))
                offset += separator
        draw_centered(draw, f"ZVV 台词拼接 · {name} · {len(bands)} 段", footer_font, width, total_height - 14, stroke=2)

    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, "PNG")
    return {
        "query": query,
        "name": name,
        "mode": mode,
        "output": str(output),
        "size": {"width": canvas.width, "height": canvas.height},
        "renderer": "pillow",
        "lines": [{"file": str(path), "title": title, "role": ""} for path, title in zip(files, lines)],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="ZVV 连续对话表情包拼接")
    parser.add_argument("query", help="用户的一句话")
    parser.add_argument("--files", default="", help="逗号分隔的素材文件名（按给定顺序）")
    parser.add_argument("--subtitles", default="", help="用 | 分隔的台词，覆盖素材自带台词")
    parser.add_argument("--mode", choices=["subtitle", "full"], default="subtitle")
    parser.add_argument("--count", type=int, default=6, help="段数（1-15）")
    parser.add_argument("--width", type=int, default=720, help="画布宽度")
    parser.add_argument("--gap", type=int, default=8, help="整图拼接时的间距")
    parser.add_argument("--library", help="素材目录")
    parser.add_argument("--out", help="输出 PNG 路径")
    parser.add_argument("--no-app", action="store_true", help="强制使用 Pillow 渲染")
    parser.add_argument("--json", action="store_true", help="以 json 输出结果")
    args = parser.parse_args()

    args.count = max(1, min(args.count, MAX_IMAGES))
    directory = common.find_library(args.library)

    files: list[Path] = []
    if args.files:
        files = resolve_files(args.files, directory)[:MAX_IMAGES]
        if not files:
            print("--files 里的素材都找不到", file=sys.stderr)
            return 1

    subtitles = [part for part in args.subtitles.split("|")] if args.subtitles else []

    items = common.load_items(directory)
    if not args.query and args.files:
        args.query = Path(files[0]).stem

    if not files:
        ranked = common.rank(args.query, items)
        picked = common.pick_sequence(ranked, args.count)[:MAX_IMAGES]
        files = [Path(entry["file"]) for entry in picked]

    lines = []
    for index, path in enumerate(files):
        if index < len(subtitles) and subtitles[index].strip():
            lines.append(subtitles[index].strip())
        else:
            lines.append(Path(path).stem)

    name = common.semantic_name(args.query, lines[0] if lines else None)
    output = Path(args.out).expanduser() if args.out else default_output(name)

    binary = None if args.no_app else find_app_binary()
    payload: dict
    if binary is not None:
        try:
            payload = run_app(binary, args, files, output)
        except Exception as error:  # noqa: BLE001 - 回退到 Pillow
            print(f"App 渲染失败（{error}），改用 Pillow", file=sys.stderr)
            payload = render_with_pillow(args.query, files, lines, args.mode, args.width, args.gap, output, name)
    else:
        payload = render_with_pillow(args.query, files, lines, args.mode, args.width, args.gap, output, name)

    payload.setdefault("lines", [])
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(f"渲染器：{payload.get('renderer')}")
        print(f"句子：{args.query}")
        print(f"命名：{payload.get('name')}   模式：{args.mode}   段数：{len(files)}")
        for index, path in enumerate(files, start=1):
            label = lines[index - 1] if index - 1 < len(lines) else Path(path).stem
            print(f"{index:2d}. {label}  ({Path(path).name})")
        print(f"输出：{output}  {payload.get('size')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
