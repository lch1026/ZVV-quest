#!/usr/bin/env python3
"""ZVV 素材库通用工具：素材定位、主题打分、语义命名。

只用标准库实现，保证在任何环境（包括没装第三方包的 Codex 会话）里都能跑。
打分思路和 macos-app 里的 Swift 实现保持一致：主题命中 + 字符二元组 + 关键词重叠。
"""

from __future__ import annotations

import os
import re
from pathlib import Path

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".heic", ".bmp", ".tiff"}
TEMPLATE_MARKERS = ("空白", "万能模板")

# 主题词典：把用户的话和素材台词映射到同一批主题上
TOPICS: dict[str, list[str]] = {
    "美国": ["美国", "美方", "白宫", "华盛顿", "美元", "中产", "美国人", "老美", "漂亮国", "灯塔国"],
    "中国": ["中国", "中华", "我国", "社会主义", "中国特色", "人民"],
    "西方": ["西方", "欧洲", "欧盟", "德国", "法国", "英国", "日本", "印度"],
    "制度": ["制度", "体制", "模式", "治理", "政治", "一党", "政策"],
    "民主": ["民主", "选举", "一人一票", "投票", "普选"],
    "自信": ["自信", "底气", "自豪", "骄傲", "实力"],
    "经济": ["经济", "增长", "发展", "脱贫", "GDP", "富裕", "生活水平", "收入", "物价", "就业", "中产"],
    "教育": ["教育", "大学", "大专", "学校", "学生", "学养", "知识", "老师", "考试"],
    "媒体": ["媒体", "舆论", "报道", "宣传", "新闻", "公知", "网络"],
    "双标": ["双标", "双重标准", "选择性", "失明", "标准"],
    "谎言": ["谎言", "撒谎", "造谣", "造假", "欺骗", "真相", "实话", "胡扯", "瞎说"],
    "笑话": ["笑话", "可笑", "好笑", "笑掉大牙", "黑色幽默", "荒缪", "荒谬", "幽默", "可悲", "滑稽"],
    "反应": ["鼓掌", "大笑", "乐", "难绷", "震惊", "震撼", "傻", "凝视", "害怕", "佩服"],
    "台湾": ["台湾", "台独", "两岸"],
    "香港": ["香港", "港人"],
    "苏联": ["苏联", "俄罗斯", "普京", "戈尔巴乔夫", "解体"],
    "军事": ["军事", "军队", "战争", "打仗", "武器", "核", "国防", "战士"],
    "腐败": ["腐败", "贪污", "官气", "套话", "官僚", "形式主义", "懒政"],
    "人权": ["人权", "自由", "平等", "公正", "道德", "法治", "法律", "正义"],
    "移民": ["移民", "出国", "留学", "绿卡", "护照"],
    "科技": ["科技", "芯片", "人工智能", "5G", "超现代", "科幻", "自主可控", "技术", "创新"],
    "历史": ["文革", "历史", "传统", "时代", "革命", "当年", "过去"],
    "爱国": ["爱国", "民族", "国家", "崛起", "复兴", "中国人"],
    "表达": ["表达", "讲话", "说话", "坦率", "说实话", "问题", "提问", "回答", "语气"],
    "地位": ["排名", "第一", "世界", "实力", "超越", "领先", "落后"],
    "阶层": ["剥削", "压迫", "阶层", "贱民", "贫富", "底层", "精英"],
    "态度": ["傲慢", "蛮横", "冷酷", "愚昧", "无底线", "嚣张", "道德优越感"],
    "敌对": ["邪恶", "势力", "手段", "阴谋", "敌人", "反制", "痛击", "围堵"],
    "胜负": ["投降", "输掉", "失败", "完蛋", "凄惨", "毁灭", "崩溃", "终结"],
    "无关": ["不在乎", "不关心", "无所谓", "不管", "懒得"],
}

PUNCTUATION = "，。！？、；：,.!?;:\"'“”‘’（）()《》<>【】[]{}-—…~·|/\\ \t\n\r"


def normalize(text: str) -> str:
    """口语别名归一化，提高主题命中率"""
    table = {
        "老美": "美国", "漂亮国": "美国", "米国": "美国", "阿美": "美国", "丑国": "美国",
        "咱们": "中国", "天朝": "中国", "东大": "中国", "老钟": "中国",
    }
    result = text.strip()
    for src, dst in table.items():
        result = result.replace(src, dst)
    return result


def match_topics(text: str) -> list[str]:
    return sorted(topic for topic, words in TOPICS.items() if any(word in text for word in words))


def bigrams(text: str) -> set[str]:
    chars = [ch for ch in text if ch not in PUNCTUATION]
    if len(chars) < 2:
        return set(chars)
    return {"".join(chars[i:i + 2]) for i in range(len(chars) - 1)}


def is_template(title: str) -> bool:
    cleaned = title.strip()
    if len(cleaned) <= 2:
        return True
    return any(cleaned.startswith(marker) or marker in cleaned for marker in TEMPLATE_MARKERS)


def find_library(explicit: str | None = None) -> Path:
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit).expanduser())
    if os.environ.get("ZVV_LIBRARY"):
        candidates.append(Path(os.environ["ZVV_LIBRARY"]).expanduser())
    here = Path(__file__).resolve()
    for parent in list(here.parents)[:6]:
        candidates.append(parent / "vv")
    candidates.append(Path.home() / "Desktop/文件/表情包/zvv连续对话表情包生成/vv")
    for candidate in candidates:
        if candidate.is_dir() and any(
            child.suffix.lower() in IMAGE_EXTS for child in candidate.iterdir() if child.is_file()
        ):
            return candidate
    raise SystemExit("找不到 vv 素材目录，请用 --library 指定，或设置 ZVV_LIBRARY 环境变量")


def load_items(directory: Path, include_templates: bool = False) -> list[dict]:
    items: list[dict] = []
    for path in sorted(directory.rglob("*")):
        if not path.is_file() or path.name.startswith("."):
            continue
        if path.suffix.lower() not in IMAGE_EXTS:
            continue
        title = path.stem
        if is_template(title) and not include_templates:
            continue
        items.append(
            {
                "path": str(path),
                "title": title,
                "topics": match_topics(title),
                "bigrams": bigrams(title),
            }
        )
    return items


def _minmax(values: list[float]) -> list[float]:
    if not values:
        return []
    low, high = min(values), max(values)
    if high - low < 1e-9:
        return [0.5 for _ in values]
    return [(value - low) / (high - low) for value in values]


def rank(query: str, items: list[dict], top: int | None = None) -> list[dict]:
    """返回带分数的候选列表（分数已做 min-max 归一化）"""
    normalized = normalize(query)
    query_bigrams = bigrams(normalized)
    query_topics = set(match_topics(normalized))

    lexical: list[float] = []
    topic: list[float] = []
    for item in items:
        union = query_bigrams | item["bigrams"]
        overlap = query_bigrams & item["bigrams"]
        lexical.append(len(overlap) / len(union) if union else 0.0)
        item_topics = set(item["topics"])
        if not query_topics:
            topic.append(0.5)
        else:
            merged = query_topics | item_topics
            topic.append(len(query_topics & item_topics) / len(merged) if merged else 0.0)

    lexical_norm = _minmax(lexical)
    topic_norm = _minmax(topic)

    scored: list[dict] = []
    for index, item in enumerate(items):
        score = lexical_norm[index] * 0.6 + topic_norm[index] * 0.4
        if item["title"] in normalized or normalized in item["title"]:
            score = min(1.0, score + 0.2)
        hit_topics = sorted(query_topics & set(item["topics"]))
        reasons = []
        if hit_topics:
            reasons.append("主题命中：" + "、".join(hit_topics))
        if lexical_norm[index] > 0.5:
            reasons.append("用词接近")
        if not reasons:
            reasons.append("话题相关度一般")
        scored.append(
            {
                "file": item["path"],
                "title": item["title"],
                "score": round(score, 4),
                "topics": item["topics"],
                "reasons": reasons,
            }
        )
    scored.sort(key=lambda entry: entry["score"], reverse=True)
    return scored[:top] if top else scored


def pick_sequence(candidates: list[dict], count: int) -> list[dict]:
    """挑出既相关又不重复的一组（MMR），并排出开场 / 承接 / 收尾"""
    if not candidates:
        return []
    count = max(1, min(count, 15, len(candidates)))
    picked = [candidates[0]]
    remaining = candidates[1:]
    while len(picked) < count and remaining:
        best_index, best_value = 0, float("-inf")
        for index, candidate in enumerate(remaining):
            redundancy = max(
                (_similarity(candidate, chosen) for chosen in picked), default=0.0
            )
            value = 0.62 * candidate["score"] - 0.38 * redundancy
            if value > best_value:
                best_value, best_index = value, index
        picked.append(remaining.pop(best_index))
    return sequence(picked)


def _similarity(left: dict, right: dict) -> float:
    union = left["bigrams"] if "bigrams" in left else bigrams(left["title"])
    other = right["bigrams"] if "bigrams" in right else bigrams(right["title"])
    merged = union | other
    lexical = len(union & other) / len(merged) if merged else 0.0
    topic_merged = set(left["topics"]) | set(right["topics"])
    topic = len(set(left["topics"]) & set(right["topics"])) / len(topic_merged) if topic_merged else 0.0
    return lexical * 0.5 + topic * 0.5


OPENERS = ("我觉得", "说实话", "坦率地讲", "大家", "人家", "我一直", "我老说", "我看了", "什么问题")
PUNCHLINES = ("难绷", "笑", "乐", "鼓掌", "震惊", "震撼", "完蛋", "投降", "输掉", "笑话", "自信", "大牙", "傻", "不屑")


def sequence(candidates: list[dict]) -> list[dict]:
    """首句像开场、末句最点题，中间用相邻相似度贪心链串起来"""
    remaining = list(candidates)
    if len(remaining) <= 1:
        for entry in remaining:
            entry["role"] = "收尾"
        return remaining

    opener = max(remaining, key=lambda c: c["score"] * 0.6 + (0.5 if c["title"].startswith(OPENERS) else 0))
    remaining.remove(opener)
    punchline = max(
        remaining,
        key=lambda c: (0.7 if any(word in c["title"] for word in PUNCHLINES) else 0) + c["score"] * 0.5,
    )
    remaining.remove(punchline)

    ordered = [opener]
    current = opener
    while remaining:
        best_index, best_value = 0, float("-inf")
        for index, candidate in enumerate(remaining):
            value = _similarity(candidate, current) * 0.7 + candidate["score"] * 0.3
            if value > best_value:
                best_value, best_index = value, index
        current = remaining.pop(best_index)
        ordered.append(current)
    ordered.append(punchline)

    for index, entry in enumerate(ordered):
        entry["role"] = "开场" if index == 0 else ("收尾" if index == len(ordered) - 1 else "承接")
    return ordered


def semantic_name(query: str, best_title: str | None = None) -> str:
    """按主题 + 最点题的一句生成语义化文件名"""
    parts = match_topics(normalize(query))[:2]
    if best_title:
        parts.append(best_title)
    name = re.sub(r"[\s/\\:*?\"<>|]+", "", "-".join(parts)) or "张维为表情包"
    return name[:24]
