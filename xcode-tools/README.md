# xcode-tools · ZVV Codex 插件

在 Codex 对话里把“接下来的语句”变成张维为（ZVV）连续对话拼接图。

## 组成

| 路径 | 说明 |
| --- | --- |
| `skills/zvv-meme/SKILL.md` | Codex 技能说明：什么时候触发、怎么挑素材、怎么排序、怎么交付 |
| `skills/zvv-meme/prompt.md` | 云端编排提示词。macOS App 也会读取同一份文件（也可在设置里指定自定义路径） |
| `scripts/zvv_common.py` | 素材库定位、主题/情绪打分、语义命名（只用标准库） |
| `scripts/zvv_select.py` | 给定句子，输出候选素材与分数，避免把 400+ 个文件名塞进上下文 |
| `scripts/zvv_stitch.py` | 拼接渲染：优先调用 macos-app 二进制，回退 Pillow |
| `.venv/` | 项目内虚拟环境（Pillow 为可选依赖） |

## 安装到 Codex

把技能目录复制或软链到 Codex 的技能目录：

```bash
mkdir -p ~/.codex/skills
ln -sfn "$PWD/xcode-tools/skills/zvv-meme" ~/.codex/skills/zvv-meme
```

之后在 Codex 里说“把这句话做成张维为表情包”即可触发 `zvv-meme` 技能。

## 依赖

```bash
cd xcode-tools
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt   # 仅 Pillow，可选
```

* 有编译好的 `macos-app/dist/ZVVQuest.app` 时，脚本会直接调用它渲染，**不需要 Pillow**。
* 没有 App、又需要出图时才需要 Pillow（`--no-app` 可强制走 Pillow 路径）。

## 用法

```bash
# 1. 拿候选（本地打分，不联网）
python3 scripts/zvv_select.py "美国人的生活水平其实没有想象中那么好" --top 24

# 2. 按语义挑好顺序后渲染
python3 scripts/zvv_stitch.py "美国人的生活水平其实没有想象中那么好" \
  --files "中国人比美国人生活的好.png,所以我觉得 美国人需要解放思想.png,这个盒饭确实比美国中产阶级吃的好.png,难绷.png" \
  --mode subtitle --out /tmp/zvv.png

# 不想手动挑素材时，脚本会自己按本地打分选并排序
python3 scripts/zvv_stitch.py "句子" --mode full --count 5 --json
```

常用参数：`--mode subtitle|full`、`--count 1-15`、`--width`、`--gap`、
`--subtitles "台词1|台词2"`、`--library`、`--out`、`--no-app`、`--json`。

环境变量：`ZVV_LIBRARY` 指定素材目录，`ZVV_APP` 指定 App 二进制路径。
