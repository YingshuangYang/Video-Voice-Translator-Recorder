# VideoVoiceTranslatorRecorder (macOS)

一个 macOS 桌面工具：监听 **系统输出音频 + 麦克风**，云端转写后自动 **中文总结 / 外语翻译成中文 / 提问自动回答**，并把记录落到本地 SQLite，支持检索与导出。

## 运行方式（推荐：Xcode）

1. 用 Xcode 打开本目录（Swift Package）。
2. 选择 scheme：`VVTRApp`，直接 Run。

## 权限

- **麦克风**：录制麦克风音频。
- **屏幕录制（Screen Recording）**：用于捕获系统音频（通过 ScreenCaptureKit）。

## 配置

应用内的“设置”页里填写：
- OpenAI API Key
- Base URL（默认 `https://api.openai.com/v1`，如使用兼容网关可修改）
- 模型（默认 `gpt-4o-mini`，可改）
- 采集分片长度（默认 10s）
配置会保存在本机 `Application Support` 下的 JSON 文件中（不写入仓库）。

