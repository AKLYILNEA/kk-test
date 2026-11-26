# Koneko

采用 Prism UI 的番剧追踪和播放客户端，支持 Android arm64 与 Windows x64。应用包名为 `com.anime.koneko`，当前版本为 `v0.0.3`。

## 开始使用

- 推荐、时间表、搜索、番剧详情与封面来自 Bangumi，可以直接浏览。
- 在「我的 → Kazumi 规则管理」打开规则仓库，安装需要的规则。也可导入 JSON 或 `kazumi://` 分享链接。播放器可选集、切换规则或线路，并在同一剧集间保留进度。
- 在「我的 → 服务与同步」配置 Bangumi Access Token、WebDAV 连接或弹弹Play App ID 和密钥。凭据由系统安全存储保存。Bangumi 同步收藏与已看剧集，WebDAV 同步追番和历史并读取 Kazumi 旧备份。
- 在播放器中缓存当前话，从「我的 → 离线缓存」查看进度或离线播放。支持直链和非加密 HLS 点播。
- Windows 使用系统 WebView2 进行页面视频解析。

## v0.0.3

- 运行入口启用真实目录、Kazumi XPath / API 规则、本地追番与多源历史。测试继续使用独立的演示数据包。
- Android 与 Windows 接入 media_kit 视频播放、Anime4K 超分、Canvas 弹幕和离线缓存。
- 历史页支持从文件导入 Kazumi JSON、JSONL 或 Hive 备份，按 Bangumi 条目合并来源并保留单集进度。
- 保留 FlClash 风格的悬浮顶栏、图标、弹簧交互、主题预览和自定义字体。

## 许可与致谢

本项目使用 GPL-3.0 许可，见 [LICENSE](LICENSE)。工具栏与导航使用 [prism_ui](https://github.com/chen08209/prism_ui)，通用字形源自 [FlClash](https://github.com/chen08209/FlClash) 与 [FlClash-Myui](https://github.com/aaANDkk/FlClash-Myui)。

规则解析器、旧版数据模型与备份格式适配来自 [Kazumi](https://github.com/Predidit/Kazumi)，移植基于本地 [Kazumi 定制分支](https://github.com/aaANDkk/Kazumi) 的 `4bef2dad`。规则目录来自 [KazumiRules](https://github.com/Predidit/KazumiRules)。Anime4K 着色器由 bloc97 提供，使用 MIT 许可并在文件头保留声明。
