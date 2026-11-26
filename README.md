# Koneko

纯净 `prism_ui` / FlClash 设计规范的跨平台番剧追踪与播放客户端（Android `arm64-v8a` & Windows `x64`）。

- **应用包名**：`com.anime.koneko`
- **当前版本**：`v0.0.1`（UI-First 首发预览版，严格剥离 `koneko_contract` / `koneko_mock`，后续无缝接入 Kazumi 核心播放、规则嗅探、弹幕、Bangumi 与 WebDAV 同步）

## 特性亮点
- **纯净 FlClash / `prism_ui` 视觉语言**：全出血图文合一卡片、无描边多色阶卡片、响应式 1–3 列追番流（彻底脱离 Kazumi 次级工具栏与单双列切换）、原生侧边栏与 iOS 26 液态玻璃 Dock。
- **1:1 FlClash 外观与自定义字体管理**：实时迷你手机预览、HCT 调色盘、导入本地 `.ttf/.otf` 字体**选后零重启秒切**，全局默认内嵌 Twemoji。
- **MIUIX 动态流体渐变关于页**：复用着色器流光背景、色散猫耳 Logo & 标题与磨砂玻璃卡片。
- **Animeko 同番多源合并历史**：按番剧 `subjectId` 合并多规则源进度，支持导入 Kazumi 备份自动合并。
