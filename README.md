# Telomi

> 原生 iOS 与 macOS 双端 AI 语音灵感速记、会议纪要与个人知识库助手。
> Native iOS & macOS AI Voice Memos, Meeting Assistant & Obsidian Knowledge Companion.

---

## 项目概览

Telomi 是一款采用 Local-First 架构的原生 SwiftUI 应用，支持在 iPhone、iPad 和 Mac 上捕获语音灵感与会议录音，并通过多模型协同完成实时转写、声纹识别、结构化提炼与知识沉淀。

### 核心特性

- **流式语音转写与离线回退**
  - 支持边录边整理，低等待延迟体验。
  - 集成云端高速模型（SenseVoice、Whisper），自动清洗噪音与语气助词。
  - 支持 Apple 端侧原生离线语音识别，无网环境下保障核心可用性。
  - 集成 FluidAudio 支持多人会议声纹分离与说话人识别。

- **AI 智能结构化与行动提取**
  - 自动从逐字稿中归纳会议要点、待办事项（Action Items）与日程活动（Calendar Events）。
  - 支持 DeepSeek、SiliconFlow 及任意兼容 OpenAI 接口规范的自定义端点。

- **系统级生态联动**
  - **Apple 提醒事项 & 日历**：通过 EventKit 双向同步，待办一键批量写入提醒事项，活动根据录音基准时间自动推导写入日历，自带去重机制。
  - **Obsidian 知识库协同**：一键生成结构化 Markdown 笔记，具备系统维护块与用户手写区域保护机制，重复导出不覆盖用户心得。

- **AI 记忆对话**
  - 基于本地历史录音与知识库笔记的问答交互。
  - 支持音频时间戳深层链接与来源回溯，点击即可跳转至对应录音位置复听。

- **隐私优先架构**
  - 所有音频原文件与逐字稿数据均持久化在本地沙盒环境。
  - API Key 仅由系统 Keychain 硬件级加密存储，不经过任何第三方中转服务。

---

## 快速上手

### 环境要求

- macOS 14.0+ 或 iOS 17.0+
- Xcode 16.0+
- Swift 5.9+

### 源码构建

1. 克隆代码仓库：
   ```bash
   git clone https://github.com/justesine/Telomi.git
   cd Telomi
   ```

2. 运行自动化测试与编译校验：
   ```bash
   chmod +x ./build_and_test.sh
   ./build_and_test.sh
   ```

3. 在 Xcode 中打开项目：
   - 打开 `MemoFlow.xcodeproj`。
   - 在项目的 **Signing & Capabilities** 页面中，选择你自己的 Apple 开发者 Team（个人免费账号或付费账号均可）。
   - 目标平台选择 `My Mac` 或你的 iPhone / iOS 模拟器，按 `Cmd + R` 即可运行。

---

## 代码结构

```
MemoFlow/
├── Sources/
│   ├── MemoFlowCore/           # 核心领域逻辑与后台服务
│   │   ├── Models/             # 录音、待办、日程与状态数据模型
│   │   └── Services/           # ASR/LLM、音频录放、EventKit、Obsidian 同步等服务
│   └── MemoFlowApp/            # 原生 SwiftUI 界面交互
│       ├── Views/              # 首页、录音弹窗、统一复核、AI 对话与设置视图
│       └── Assets.xcassets     # 应用图标与主题资产
├── Tests/
│   └── MemoFlowCoreTests/      # PRD 核心验收测试与稳定性测试套件
├── MemoFlow.xcodeproj          # Xcode 工程配置文件
└── Package.swift               # Swift Package Manager 依赖清单
```

---

## 许可证

本项目采用 MIT 许可证，详情请参阅 [LICENSE](LICENSE)。
