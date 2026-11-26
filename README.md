# Koneko

纯净 `prism_ui` / FlClash 设计规范的跨平台番剧追踪与播放客户端（Android `arm64-v8a` & Windows `x64`）。

- **应用包名**：`com.anime.koneko`
- **当前版本**：`v0.0.2`（UI 预览版，使用 `koneko_contract` 与 `koneko_mock`）

## 特性亮点
- **纯净 FlClash / `prism_ui` 视觉语言**：全出血图文合一卡片、无描边多色阶卡片、响应式 1–3 列追番流（彻底脱离 Kazumi 次级工具栏与单双列切换）、原生侧边栏与 iOS 26 液态玻璃 Dock。
- **FlClash 外观与自定义字体管理**：浮动渐隐顶栏、矢量图标、弹簧按压反馈、实时主题预览与 HCT 调色盘。自定义 `.ttf/.otf` 字体即时生效，Emoji 使用内置 Twemoji。
- **MIUIX 动态流体渐变关于页**：复用着色器流光背景、色散猫耳 Logo & 标题与磨砂玻璃卡片。
- **Animeko 同番多源合并历史**：按番剧 `subjectId` 合并多规则源进度，支持导入 Kazumi 备份自动合并。

## v0.0.2

- 修复混排文字的空格异常，正文按平台和中文语种选择字体，Emoji 单独用 Twemoji 渲染。
- 同步 FlClash-Myui 的常用字形、弹簧工具栏按钮和滚动顶栏渐隐。手机二级页使用弹簧推入和交互返回，桌面页在侧栏右侧淡入。
- 主导航保留各页滚动和筛选状态，快速切换时直接过渡到目标页。

## 许可与致谢

本项目使用 GPL-3.0 许可，见 [LICENSE](LICENSE)。工具栏与导航使用 [prism_ui](https://github.com/chen08209/prism_ui)。通用字形源自 [FlClash](https://github.com/chen08209/FlClash) 与 [FlClash-Myui](https://github.com/aaANDkk/FlClash-Myui)，本次以本地 FlClash 定制分支 `2b43f5795` 为参考。
