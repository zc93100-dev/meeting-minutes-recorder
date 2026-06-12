# 🎙️ 会议纪要录音器

> 浏览器录音 → 自动合并 → AI 语音识别 → 生成结构化会议纪要

一个开箱即用的本地会议录音 + 智能纪要工具。**在浏览器里录音**，后端自动合并、转写、生成结构化会议纪要，最后输出到桌面。

---

## 功能

- 🎤 **浏览器分段录音** — 无需安装额外客户端，打开网页即可录制
- 🔗 **自动合并** — 多段录音自动合并为一个完整 MP3
- 🧠 **AI 语音识别** — 基于模力方舟 SenseVoiceSmall 模型，支持自动语言识别
- 📝 **AI 会议纪要** — 基于 DeepSeek V4 Flash 模型，生成结构清晰的会议纪要（摘要、议题、关键讨论、待办事项等）
- 📂 **自动输出到桌面** — 处理完成后自动在桌面创建 `会议纪要/` 文件夹，保存完整录音 + 主题命名的 .docx 纪要
- 🖥️ **macOS 原生 App** — AppleScript 构建，双击启动、Cmd+Q 关闭，不占后台内存
- 💻 **纯本地运行** — 所有数据保存在本地，ASR 和 AI 通过 API 云端处理

## 截图

![界面预览](https://via.placeholder.com/720x400/1a1a1a/5b9aff?text=🎙️+会议纪要录音器)

## 快速开始

### 📦 一键 App（macOS 推荐）

构建一个真正的 macOS 原生应用，**像普通软件一样双击打开、Cmd+Q 关闭**：

```bash
# 1. 确保已安装依赖（仅首次）
npm install
cp .env.example .env   # 填入 API Key

# 2. 构建 App
bash build.sh

# 3. 打开 build/ 目录，双击「会议纪要录音器.app」
# 或者拖到 Dock 固定，以后一键启动
```

### 命令行方式

```bash
# 安装依赖
npm install
cp .env.example .env

# 启动
npm start

# 浏览器打开 http://localhost:19924
# 注意：终端不能关，否则服务停止
```

### 前置要求

- [Node.js](https://nodejs.org/) ≥ 18
- [FFmpeg](https://ffmpeg.org/)（音频合并用）
  - macOS: `brew install ffmpeg`
  - Linux: `sudo apt install ffmpeg`
  - Windows: 下载 [ffmpeg.exe](https://ffmpeg.org/download.html) 并加入 PATH

### 安装

```bash
# 1. 克隆项目
git clone https://github.com/zc93100-dev/meeting-minutes-recorder.git
cd meeting-minutes-recorder

# 2. 安装依赖
npm install

# 3. 配置 API Key
cp .env.example .env
# 编辑 .env，填入你的 API Key（见下方说明）
```

### 获取 API Key

| 服务 | 用途 | 获取方式 | 是否必填 |
|------|------|----------|---------|
| **模力方舟 (Moark)** | 语音识别 ASR | [moark.com](https://www.moark.com) 注册 → 控制台创建 API Key | ✅ 必填 |
| **DeepSeek** | 生成会议纪要 | [platform.deepseek.com](https://platform.deepseek.com) 注册 | ❌ 选填（也可在页面上填写） |

### 启动

```bash
npm start
```

浏览器打开 **http://localhost:19924** 即可使用。

### 什么情况下页面打不开？

- **终端关了 / 电脑重启** → 运行 `npm start` 的终端进程结束，页面就打不开了
- **解决方法**：用 `build.sh` 构建 .app，**双击打开、Cmd+Q 关闭**，像普通软件一样使用

## 使用方法

1. 🔑 在页面顶部填入 API Key（也可提前写入 .env）
2. 🎤 点击红色录音按钮开始录音，再次点击停止
3. 🔄 可多次点击录音按钮录制多段（自动追加）
4. 🚀 点击「开始处理」等待合并 → 识别 → 生成纪要
5. 📂 处理完成后，桌面自动出现 `会议纪要/YYYY-MM-DD HH:mm (会议纪要)/` 文件夹
   - `merged.mp3` — 完整录音
   - `会议主题.docx` — 结构化会议纪要

## 桌面输出结构

```
~/Desktop/会议纪要/
├── 2026-06-12 11:00 (会议纪要)/
│   ├── merged.mp3                ← 完整录音
│   └── 会议概要.docx             ← 会议纪要（主题命名）
└── 2026-06-13 15:30 (会议纪要)/
    ├── merged.mp3
    └── AI赋能实践分享.docx
```

## 技术栈

| 层 | 技术 |
|----|------|
| 前端 | 原生 HTML + CSS + JavaScript |
| 后端 | Express.js |
| 音频处理 | FFmpeg |
| 语音识别 | Moark SenseVoiceSmall API |
| 纪要生成 | DeepSeek V4 Flash API |
| 文档输出 | macOS textutil（.md → .docx） |

> **注意**：.docx 生成依赖 macOS 内置的 `textutil` 命令。其他系统可手动将 `meeting-minutes.md` 转换为 Word 文档。

## 项目结构

```
meeting-minutes-recorder/
├── server.js          # 后端服务（核心逻辑）
├── public/
│   └── index.html     # 前端页面
├── package.json
├── .env.example       # API Key 配置模板
└── .gitignore
```

## 隐私说明

- 录音数据保存在本地 `sessions/` 目录
- 语音识别通过模力方舟 API 处理（音频会上传到云端）
- 纪要生成通过 DeepSeek API 处理（仅发送转写文本）
- 不会在本地存储之外持久化任何数据
- 处理完成后自动输出到桌面，可随时删除

## License

MIT
