# macos-app · ZVV 连续对话表情包生成器（macOS）

SwiftUI 桌面应用：本地语义理解一句话 → 从 `vv/` 里挑素材 → 排成连续对话 → 拼成一张 PNG →
预览 + 自动复制到剪贴板 + 落盘到 cache 目录。

## 构建

```bash
./build.sh            # 编译并打包 dist/ZVVQuest.app
./run.sh              # 构建并运行
./tools/make-icon.sh  # 只重新生成 Resources/AppIcon.icns
```

环境变量：

| 变量 | 作用 |
| --- | --- |
| `ZVV_SDK` | 指定编译用的 macOS SDK（不指定则自动探测可用 SDK） |
| `ZVV_LIBRARY` | 打包时内置的素材目录（默认自动往上找 `vv/`） |
| `ZVV_DEPLOY_TARGET` | 覆盖编译 target，默认 `arm64-apple-macos<SDK 主版本>.0` |

不需要安装 Xcode：只用 Command Line Tools 的 `swiftc` 编译，构建脚本自己组装 `.app`。

## 命令行模式

```bash
dist/ZVVQuest.app/Contents/MacOS/ZVVQuest --help
dist/ZVVQuest.app/Contents/MacOS/ZVVQuest --generate "句子" --mode subtitle --count 6 --out /tmp/zvv.png
dist/ZVVQuest.app/Contents/MacOS/ZVVQuest --generate "句子" --files "a.png,b.png" --json
```

`xcode-tools/scripts/zvv_stitch.py` 在没有 Pillow 的环境下会直接调用这里的二进制，
保证命令行与 GUI 渲染结果一致。

## 代码结构

| 文件 | 职责 |
| --- | --- |
| `Sources/ZVVQuest/Models.swift` | 模式、后端、素材、候选、方案等数据模型 |
| `Sources/ZVVQuest/Settings.swift` | 设置持久化（UserDefaults）与路径约定 |
| `Sources/ZVVQuest/MemeLibrary.swift` | 扫描素材库、分词、主题/情绪标注、素材目录定位 |
| `Sources/ZVVQuest/Engine/TextEmbedder.swift` | 系统中文句向量封装（带缓存） |
| `Sources/ZVVQuest/Engine/VectorMath.swift` | Metal 计算内核 + Accelerate CPU 实现 + 一致性自检 |
| `Sources/ZVVQuest/Engine/SemanticEngine.swift` | 四路打分融合（句向量 / 关键词 / 主题 / 情绪） |
| `Sources/ZVVQuest/Engine/DialoguePlanner.swift` | MMR 选材 + 相邻相似度排序 + 首尾角色校正 + 语义命名 |
| `Sources/ZVVQuest/Engine/CloudPlanner.swift` | DeepSeek 调用（JSON 模式）与结果映射 |
| `Sources/ZVVQuest/Engine/SkillPrompt.swift` | 提示词来源（项目内 md / 内置） |
| `Sources/ZVVQuest/Engine/SkillCache.swift` | 本地 skill 缓存，避免重复调用 API |
| `Sources/ZVVQuest/Engine/GenerationCoordinator.swift` | 主流程编排与状态发布 |
| `Sources/ZVVQuest/Render/*` | 图片解码与两种拼接渲染 |
| `Sources/ZVVQuest/Store/GenerationStore.swift` | cache 目录、语义命名、索引、删除 |
| `Sources/ZVVQuest/System/*` | 硬件监控与剪贴板 |
| `Sources/ZVVQuest/Views/*` | 生成 / 图库 / 设置界面与监控图表 |
| `Sources/ZVVQuest/CLI.swift` | 命令行入口 |

## 设置项

* 拼接方式、画布宽度、整图间距、字幕字号、裁切比例
* 台词段数（1–15）、理解来源（本地 / 云端）、推理硬件（自动 / GPU / CPU）
* DeepSeek 接口地址、模型、API Key、thinking 开关、skill 缓存开关、skill 提示词路径
* 素材库目录、缓存目录、生成后是否自动复制到剪贴板
