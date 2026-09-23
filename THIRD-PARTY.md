# 第三方代码与依赖说明

## 结论

本项目当前版本**没有拷贝任何第三方项目的代码或数据**：语义打分、对话编排、Metal/Accelerate 双后端、
两种拼接渲染、Codex 插件脚本全部为本项目自行实现。下面记录开发前的调研过程、结论，
以及真正用到的第三方**依赖**（库，而不是源码拷贝）。

## 一、GitHub 同类项目调研（2026-09）

按需求要求检索了“张维为表情包 / 表情拼接”相关开源项目，检索方式：
`GET https://api.github.com/search/repositories?q=张维为+表情包`。

| 项目 | 协议 | 说明 | 是否借鉴代码 |
| --- | --- | --- | --- |
| [da-cross/vv_meme_bot](https://github.com/da-cross/vv_meme_bot) | 无协议 | 本地全自动张维为表情包查找 | 否（无协议，不可借鉴） |
| [yys-y/zhangvv-meme-skill](https://github.com/yys-y/zhangvv-meme-skill) | MIT | 面向 Agent 的张维为表情包 skill + 图鉴 | 否 |
| [LYB926/astrbot_plugin_zvv_quest](https://github.com/LYB926/astrbot_plugin_zvv_quest) | MIT | AstrBot 张维为表情包查询插件 | 否 |
| [IcyDesert/zvvbot](https://github.com/IcyDesert/zvvbot) | GPL-3.0 | 关键词检索张维为表情包（Go） | 否（GPL-3.0 与本项目 MIT 不兼容） |
| [bomomoQWQ/astrbot_plugin_zvv](https://github.com/bomomoQWQ/astrbot_plugin_zvv) | MIT | 语义搜索 416 张表情包 | 否 |

### 为什么最终没有直接使用

* `vv_meme_bot`、`zvvbot` 需要各自配套的素材库与索引文件（`text_to_filepath.json`、OCR 文本等），
  与本项目 `vv/` 目录的素材集合、命名体系并不一致；前者的 `txts.json` / `text_to_filepath.json`
  与本机素材文件名交集为空，直接套用会导致大量错配。
* 本项目素材含义直接取自文件名（需求 3），已有等价且更简单可靠的语义来源，
  引入外部索引反而增加不确定性和协议负担。
* `zvvbot` 为 GPL-3.0，若拷贝其代码会使本项目必须整体改为 GPL-3.0；
  `vv_meme_bot` 未声明协议，按默认版权规则不可借鉴。

### 参考过的“思路”（非代码）

* `yys-y/zhangvv-meme-skill` 的 `MEME_CATALOG.md` 把表情包按**情绪/场景**分类
  （震惊/无语、嘲讽/质疑、担忧/害怕、国际/比较、自信/傲慢、崩坏/完了……）。
  本项目借鉴了这个“按口吻分类”的想法，在 `Sources/ZVVQuest/TopicLexicon.swift`
  中自行编写了情绪基调词表与判定规则（`tones`），用于让收尾台词落在同一种情绪上。
  该词表与判定逻辑均为本项目原创，未复制其文本。

## 二、运行时依赖（库）

| 依赖 | 协议 | 用途 | 备注 |
| --- | --- | --- | --- |
| Apple `SwiftUI` / `AppKit` / `Charts` / `Metal` / `Accelerate` / `NaturalLanguage` / `IOKit` | 系统框架 | 界面、图表、GPU 计算、SIMD 计算、中文句向量、GPU 利用率 | 随 macOS 提供 |
| [Pillow](https://python-pillow.org/)（可选） | MIT-CMU | `xcode-tools` 在**没有编译 App** 的环境里做纯 Python 渲染回退 | 仅 `xcode-tools/requirements.txt`，已在 `xcode-tools/.venv` 安装 |
| DeepSeek API（可选） | 服务条款 | 云端语义编排（默认模型 `deepseek-flash`） | 仅在用户开启“云端大模型”并填写 API Key 时调用 |

## 三、素材

`vv/` 目录下的表情包图片为用户自带素材，不在本项目的 MIT 授权范围内。
