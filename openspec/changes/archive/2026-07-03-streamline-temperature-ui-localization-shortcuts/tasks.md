## 1. 语言设置与资源基础

- [x] 1.1 在 `MacWatchCore` 增加 `AppLanguage`，扩展 `AppSettings` 默认值、初始化器和向后兼容解码，确保旧设置迁移为 `system` 且其他字段不变
- [x] 1.2 为语言设置默认值、JSON 往返、旧版 JSON 迁移和未知/损坏数据回退补充 Core 测试
- [x] 1.3 在 `Package.swift` 声明 `MacWatchApp` localization resources，并建立 English 与 `zh-Hans` 资源文件
- [x] 1.4 在 App 展示层实现单一 locale/localized-string resolver，覆盖 SwiftUI `Locale` 注入、普通字符串格式化和 AppKit 标题解析

## 2. 全应用中英文覆盖

- [x] 2.1 在 Settings 增加“跟随系统 / 中文 / English”选择器并接入持久化与即时刷新
- [x] 2.2 本地化 Popup、Dashboard、sidebar、兼容性页和各温度详情/趋势页的标签、状态、原因、时间及格式化文本
- [x] 2.3 本地化 Settings、清除历史确认、首次启动引导、窗口标题和菜单栏操作，并保持 CLI、JSON、日志和验收标识不变
- [x] 2.4 增加语言解析、关键文案、格式化及运行时设置即时生效测试，验证 unsupported/readFailed/stale 的中英文输出

## 3. Popup 与 Dashboard 精简

- [x] 3.1 重构温度概览展示模型，使正常项只暴露标题、主温度和可选平均温度，异常项额外暴露本地化状态与必要原因
- [x] 3.2 精简 Popup：删除来源、正常状态和逐项更新时间，增加唯一整体更新时间，并压缩行距、内边距和 popover 内容尺寸
- [x] 3.3 精简 Dashboard 摘要和设备卡片：删除正常状态、来源、逐卡更新时间及无价值重复信息，保留唯一整体更新时间和异常说明
- [x] 3.4 将 Dashboard 卡片改为自适应 2–3 列与自然高度，调整主窗口默认/最小尺寸，并验证中英文正常及异常内容不截断
- [x] 3.5 小幅统一详情页的间距和文案层级，确认来源、采样信息、最近状态、统计、趋势和时间仍完整可见
- [x] 3.6 更新展示层测试，分别断言正常状态静默、异常状态明确、整体时间只出现一次、CPU/GPU 平均温度保留和无误导性旧值

## 4. macOS 窗口命令

- [x] 4.1 在现有 AppKit 生命周期中建立本地化 application/window 菜单，并仅注册 `⌘W`、`⌘,`、`⌘Q`
- [x] 4.2 将 `⌘W` 接到 key-window responder chain，将 `⌘,` 接到单例 Settings 窗口，将 `⌘Q` 接到标准终止生命周期
- [x] 4.3 在语言变化时刷新菜单与已创建窗口标题，并增加菜单结构、快捷键唯一性、窗口关闭不退出和 Settings 单例行为测试

## 5. 验证与文档

- [x] 5.1 运行 `./scripts/test.sh`，修复 SwiftPM 资源打包、单元测试或 Stats 边界回归
- [x] 5.2 打包并分别以中文、English、跟随系统检查 Popup、Dashboard、Settings、详情页、首次引导和三个快捷键的真实 `.app` 行为
- [x] 5.3 运行 `dashboard-open`、`popup-open`、`first-run-guide`、`launch-main-window-on-start-enabled` 和 `launch-main-window-on-start-disabled` 相关阶段 7 验收
- [x] 5.4 若语言设置、资源目录或窗口验证方式影响开发上手流程，同步更新 `README.md`
