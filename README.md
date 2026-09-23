<img src="macos-app/Resources/AppIcon.png" width="132" align="right" alt="ZVV-quest 图标">

# ZVV-quest

> **⚠️ 本项目由 DeepSeek 等 AI 辅助构建**：代码、文档与素材整理均在 AI 协助下完成，请自行评估适用性。

把一句普通的中文，变成一张**张维为（ZVV）连续对话表情包拼接图**。

项目包含两个部分：

| 目录 | 内容 |
| --- | --- |
| `macos-app/` | 带界面的 macOS 本地应用：本地语义理解 + 云端大模型可选 + 两种拼接方式 + 硬件资源监控图表 |
| `xcode-tools/` | Codex 插件（skill + 脚本）：在对话里把“接下来的语句”直接变成拼接图 |

素材含义来自文件名：`vv/` 目录里每一张图的**文件名就是它的台词**，例如 `我觉得这就是一种自信.png`。
仓库本身不放素材，构建脚本会依次在 `ZVV-quest/vv`、仓库同级的 `../vv`（当前开发机上就是
`zvv连续对话表情包生成/vv`）等处自动查找，也可以用 `ZVV_LIBRARY` 或应用设置里的“素材库目录”指定。

---

## 0. 下载安装（第一版 v0.1.0）

到 [Releases](https://github.com/lch1026/ZVV-quest/releases/latest) 下载
`ZVVQuest-0.1.0-macos.zip`，解压后把 `ZVVQuest.app` 拖进「应用程序」即可。

* 通用二进制（Apple 芯片 + Intel），最低 macOS 14.0。
* 应用是**临时签名**（没有做 Apple 公证），首次打开如果提示“无法验证开发者”，
  在图标上右键 →「打开」；或者执行一次：

  ```bash
  xattr -dr com.apple.quarantine /Applications/ZVVQuest.app
  ```

* 分发包里已经内置了 `vv/` 素材库（433 张），下载后开箱可用，不需要再找素材。

### 初始 vv 表情包

仓库根目录的 **`vv.zip`（约 33 MB，433 张，即本项目的「初始 vv 表情包」）** 就是最初那套原始表情包合集。
解压后得到 `vv/` 目录，放到仓库根目录同级即可；构建脚本会自动查找并打进 App
（找不到 `vv/` 时，`macos-app/build.sh` 也会自动解压 `vv.zip`）。

---

## 1. 快速开始

### 1.1 构建并运行 macOS 应用

```bash
cd macos-app
./build.sh          # 只用 Command Line Tools，不需要装 Xcode
open dist/ZVVQuest.app
```

构建脚本会自动挑选可用的 macOS SDK、把 `vv/` 素材库打进 App（也可以在设置里另外指定目录）、生成并嵌入 App 图标，
并默认产出 **arm64 + x86_64 通用二进制**（最低 macOS 14.0，可用 `ZVV_ARCHS` / `ZVV_DEPLOY_MIN` 调整）。

图标由根目录的 `图标.png` 提供：它被复制为 `macos-app/Resources/AppIcon.png`，
由 `macos-app/tools/make-icon.sh` 转成 `Resources/AppIcon.icns` 后打进 App。

### 1.2 命令行模式（脚本与插件共用同一套引擎）

```bash
./dist/ZVVQuest.app/Contents/MacOS/ZVVQuest \
  --generate "美国人的生活水平其实没有想象中那么好" \
  --mode subtitle --count 6 --out /tmp/zvv.png
```

也可以直接指定素材（Codex 插件按语义挑好素材后走这条路径）：

```bash
./dist/ZVVQuest.app/Contents/MacOS/ZVVQuest \
  --generate "句子" --files "中国人比美国人生活的好.png,难绷.png" --json
```

### 1.3 在 Codex 里使用插件

```bash
python3 xcode-tools/scripts/zvv_select.py "美国人的生活水平其实没那么好" --top 24   # 拿候选
python3 xcode-tools/scripts/zvv_stitch.py "句子" --files "a.png,b.png" --out /tmp/zvv.png
```

把 `xcode-tools/skills/zvv-meme/` 装到 Codex（见 `xcode-tools/README.md`），之后直接说“把这句话做成张维为表情包”即可。

---

## 2. 功能说明

### 2.1 两种拼接方式

* **整图竖向拼接**：每张表情包按统一宽度等比缩放后自上而下拼接。
* **台词拼接**：裁切每张表情包的中部画面，压成一条条字幕卡（效果参考 `台词拼接实例.png`）。

两种模式都遵守 **单次上限 15 张**，避免生成图片过大。

### 2.2 语义理解

* **本地模式（完全离线）**：系统 `NaturalLanguage` 中文句向量（640 维）+ 关键词重叠 + 主题词典 + 情绪基调，四路加权打分。
* **云端模式**：调用 DeepSeek（默认 `deepseek-flash`）做一次编排，拿到素材序号、顺序与命名。提示词优先读取 `xcode-tools/skills/zvv-meme/prompt.md`（App 与插件共用同一份 skill）。

### 2.3 推理硬件可选

`自动选择 / GPU（Metal）/ CPU（Accelerate）` 三档。向量相似度有 GPU 与 CPU 两套实现，界面会显示本次耗时与**双后端最大偏差**，设置页提供一致性自检入口。

### 2.4 硬件资源监控

底部常驻微型动态折线图，每秒轮询：CPU 占用、内存占用、GPU 占用（GPU 利用率来自 IOKit `IOAccelerator`，不可读时改看 GPU 占用内存）。

### 2.5 结果与缓存

* 生成后自动预览，并**自动复制到剪贴板**（可在设置里关闭）。
* 图片写入缓存目录（默认 `~/Library/Caches/ZVVQuest`），按语义命名，例如 `ZVV-经济-美国-中国人比美国人生活的好-260923-2210.png`。
* “图库”页可以浏览、复制、按张删除或清空。

### 2.6 云端调用的省钱设计

* 云端只发“用户句子 + 本地筛出的候选台词清单”，**一次请求**完成挑选、排序、命名；
* 同一句话 + 同一套参数会命中本地 skill 缓存，命中时**完全不发请求**（设置页可清空缓存）。

---

## 3. 目录结构

```text
ZVV-quest/
├── vv.zip                     初始 vv 表情包合集（433 张，解压后得到 vv/）
├── macos-app/                 macOS 应用（SwiftUI，直接 swiftc 构建，无需 Xcode）
│   ├── Sources/ZVVQuest/
│   │   ├── Engine/            语义引擎、对话编排、云端调用、skill 缓存
│   │   ├── Render/            整图拼接 / 台词拼接渲染
│   │   ├── Store/             缓存目录与索引
│   │   ├── System/            硬件监控、剪贴板
│   │   ├── Views/             生成 / 图库 / 设置 三个界面
│   │   └── CLI.swift          命令行入口（插件复用）
│   ├── Resources/             AppIcon.png（图标源文件）+ AppIcon.icns（构建产物）
│   ├── tools/                 图标生成脚本（png → icns）
│   ├── build.sh               构建 + 打包 .app
│   └── run.sh                 构建并运行
└── xcode-tools/               Codex 插件
    ├── skills/zvv-meme/       SKILL.md（技能说明）+ prompt.md（云端提示词，App 共用）
    ├── scripts/               候选打分、拼接渲染（Python）
    └── .venv/                 本地虚拟环境（Pillow 为可选依赖）
```

---

## 4. 需求对照

| 需求 | 实现位置 |
| --- | --- |
| ① 整图竖向拼接 / 台词拼接 | `Sources/ZVVQuest/Render/MemeRenderer.swift`，界面「拼接方式」 |
| ② GPU 加速 / CPU 加速 / 自动选择 | `Sources/ZVVQuest/Engine/VectorMath.swift`（Metal 内核 + Accelerate），设置页可跑双后端一致性自检 |
| ③ 本地处理或连接大模型 API | `Sources/ZVVQuest/Engine/CloudPlanner.swift`（DeepSeek `deepseek-flash`，OpenAI 兼容 `/chat/completions` + JSON 模式）；本地 skill 提示词与缓存降低调用次数 |
| ④ 微型硬件资源动态图表 | `Sources/ZVVQuest/System/HardwareMonitor.swift` + `Views/MonitorStrip.swift` |
| ⑤ 生成后预览并自动复制到剪贴板 | `Views/ComposeView.swift`、`System/Clipboard.swift` |
| ⑥ 单次最多 15 张 | `AppSettings.maxImagesLimit`，脚本侧 `MAX_IMAGES` |
| ⑦ cache 目录 + 语义命名 + 浏览/删除 | `Store/GenerationStore.swift` + `Views/LibraryView.swift` |
| ⑧ Codex 插件 | `xcode-tools/`（skill + 脚本，复用 App 的渲染器） |

---

## 5. 已知环境问题

这台机器的 Command Line Tools 有一个组合问题：**新 SDK 把 SwiftUI 的 `@State` 等属性包装器改成了宏（实现在 `SwiftUICore` 里），而 CLT 不带 `SwiftUIMacros` 插件**（装了完整 Xcode 才有）。因此 `build.sh` 会拿编译器实际试编译一段带 `@State` 的代码，自动挑选可用的 SDK；结果缓存在 `macos-app/build/sdk-choice.txt`，可用环境变量 `ZVV_SDK` 覆盖。编译时始终指定可写的 `-module-cache-path`，否则会看到误导性的 “this SDK is not supported by the compiler”。

另外，系统的 `iconutil` 在受限沙箱里会报 `Invalid Iconset.`（同样的 iconset 在沙箱外正常），所以图标只有在生成 `Resources/AppIcon.icns` 时才需要在正常终端里跑一次；`.icns` 已经提交进仓库，日常构建不需要重新生成。

---

## 6. 开源协议

本项目使用 MIT 协议，见 [LICENSE](LICENSE)。

开发前调研了 GitHub 上同类开源项目，结论与清单见 [THIRD-PARTY.md](THIRD-PARTY.md)：**当前代码没有拷贝任何第三方代码或数据**，全部为本项目自行实现。

---

## 7. 素材来源声明

本项目使用的表情包合集为**其他开源项目以及互联网上的免费资源**，版权归原作者所有，本项目仅作学习交流使用。
**如侵犯著作权，请联系删除。**
