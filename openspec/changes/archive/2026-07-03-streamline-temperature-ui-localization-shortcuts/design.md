## Context

MacWatch 当前以手工 `NSApplication` 生命周期运行：`AppDelegate` 管理主窗口和设置窗口，`MenuBarController` 管理 `NSStatusItem` 与 SwiftUI Popup，主窗口内部使用 `NavigationSplitView`。Popup 和 Dashboard 直接展示 `TemperatureOverviewSnapshot.Row` 的来源、逐项时间和 `Valid` 状态，造成重复；主窗口最小尺寸固定为 920×640，卡片固定三列且最小高度较大。

本次变更横跨 SwiftUI 展示、AppKit 窗口/菜单、`AppSettings` 持久化和 SwiftPM resources。实现必须继续满足：无效读数不能伪装为温度、UI 不直接访问采集或 SQLite、内部温度保持摄氏度、StatsAdapter 边界不变，并支持 macOS 13。

## Goals / Non-Goals

**Goals:**

- 让 Popup 和 Dashboard 首先回答“各硬件现在多少度”，正常状态不展示实现细节。
- 将异常信息保留在对应硬件上下文中，并把来源、采样等完整信息留在详情页。
- 使用一套可测试的中英文资源和语言解析机制，实现无需重启的切换。
- 在现有 AppKit 应用生命周期中提供标准、可发现的 macOS 菜单与快捷键。
- 通过自适应网格和内容驱动尺寸减少空白，同时保留窗口缩放与恢复使用习惯。

**Non-Goals:**

- 不改变温度指标、采集器、刷新调度、趋势存储、能力检测或数据来源优先级。
- 不新增温度阈值、颜色告警、通知、导出、联网或 Post-MVP 指标。
- 不重写为 SwiftUI `App`/`Scene` 生命周期，不引入第三方本地化或窗口框架。
- 不为详情页做结构重设计，也不增加除 `⌘W`、`⌘,`、`⌘Q` 之外的快捷键。

## Decisions

### 1. 分离“温度概览”与“诊断详情”展示模型

为 Popup/Dashboard 引入专用的本地化展示模型：正常项仅提供标题、主温度和可选平均温度；异常项额外提供状态与必要原因。页面级 snapshot 负责统一更新时间。`sourceText`、逐项更新时间和正常状态不再进入概览视图层，但原始 snapshot/详情格式化能力继续保留给详情页和兼容性页。

这样可以在模型测试中断言“正常静默、异常明确”，避免仅靠视图条件分支产生回归。备选方案是直接在两个 View 中隐藏现有字段，但会复制规则并使本地化与测试更脆弱。

### 2. 使用自适应 Dashboard 网格与内容约束确定窗口尺寸

Dashboard 使用带最小卡片宽度的 adaptive grid，正常卡片不再设置 150pt 的固定最小高度；异常原因出现时允许卡片自然增高。主窗口初始尺寸和最小尺寸在真实内容测量后下调，以“常见窗口宽度可稳定显示 2–3 列、首屏可看到趋势入口、最小尺寸不截断异常文本”为验收依据，不假设单一显示器尺寸。Popup 根据精简后的行高下调固定宽高，并保证所有指标与底部操作无需额外滚动。

继续使用系统 sidebar、语义颜色和 material，不引入自绘窗口 chrome。备选方案是固定三列并单纯缩小字体，这会降低可读性且在窄窗口中更容易截断。

### 3. 在 Core 保存语言枚举，在 App 层解析 Locale 与字符串

`MacWatchCore` 增加可 Codable 的 `AppLanguage`（`system`、`zhHans`、`english`）并加入 `AppSettings`。自定义解码在旧 JSON 缺少字段时回退 `.system`，保留其他已存设置。Core 只保存偏好，不依赖 UI localization API。

`MacWatchApp` 提供单一语言解析/本地化入口：SwiftUI 根视图注入由设置解析出的 `Locale`；需要构造普通 `String` 的展示模型、AppKit 窗口标题和菜单项通过同一 bundle/localization resolver 取值。语言设置变化沿现有 `runtime.settingsDidChange` 通知刷新 Popup、状态项、菜单和已创建窗口，避免同时维护第二套语言状态。

资源使用 SwiftPM target resources 中的 English 与 `zh-Hans` 本地化文件，并在 `Package.swift` 显式声明。备选方案是只设置 `AppleLanguages` 并要求重启，不符合即时生效；在代码中维护中英字典则失去系统资源校验、复数和格式化能力。

### 4. 本地化边界覆盖用户文本，不改协议标识

所有用户能看到的文案改用稳定 localization key，包括状态/原因、窗口与菜单、首次引导、兼容性、设置和趋势标签。温度领域 raw value、metric name、CLI 参数、JSON key、测试场景名和日志保持英文稳定值，避免语言选择破坏持久化或自动化验收。

格式化字符串使用占位符而非拼接英文前缀；温度数值继续沿用单位设置，时间格式通过选定 Locale 输出。备选方案是仅翻译本次截图页面，会让切换后的应用形成中英混杂界面，不满足“应用语言”语义。

### 5. 使用 AppKit 主菜单接入标准 responder-chain 命令

由于项目不是 SwiftUI `App` scene，命令不通过 `.commands` 拼装，而由 `AppDelegate` 建立原生 application/window 菜单。`⌘W` 使用 responder chain 的 `performClose:` 作用于 key window；`⌘,` 定向调用现有单例设置窗口入口；`⌘Q` 调用标准 terminate action，让既有 will-terminate 生命周期继续执行。菜单标题在语言变化时原位更新，快捷键不变。

备选方案是在每个 View 上分别加 `.keyboardShortcut`，会造成作用域冲突、Popup 焦点不一致，并削弱菜单可发现性。采用 AppKit 仅限当前已由 AppKit 持有的菜单与窗口边界，不向 SwiftUI 内容扩散。

## Risks / Trade-offs

- [即时切换时存在遗漏的硬编码字符串] → 先用 `rg` 建立用户文案清单，集中资源 key，并增加中英文关键页面/展示模型测试。
- [覆盖 `settingsDidChange` 现有闭包可能漏掉窗口或菜单刷新] → 将设置变化汇总到 AppDelegate 的单一处理函数，再分发状态项、窗口标题、菜单与现有调度更新；保留原行为测试。
- [旧设置因新增非可选字段解码失败并整体重置] → 为 `AppSettings` 增加向后兼容解码测试，明确断言原有五项值不变且语言为 `.system`。
- [移除正常状态后用户难以判断数据是否新鲜] → 页面保留唯一整体更新时间；任何 stale 状态仍在对应指标上明确显示。
- [异常原因长度导致中文或英文卡片高度不一致] → 使用自然高度、自适应列和多行文本，不依赖固定卡片高度；用两种语言检查最小窗口。
- [macOS 13 下部分现代 SwiftUI window API 不可用] → 窗口继续由现有 `NSWindow` 管理，只采用当前部署目标可用的 SwiftUI 布局 API。

## Migration Plan

1. 先扩展 `AppLanguage` 与 `AppSettings` 兼容解码并补迁移测试，确保旧设置安全读取。
2. 添加并打包本地化资源及 resolver，将用户文案分批迁移；在英语默认路径保持现有验收协议不变。
3. 引入精简概览展示模型并替换 Popup/Dashboard，再调整主窗口与 Popup 尺寸。
4. 建立原生主菜单和三个快捷键，接入语言刷新。
5. 运行 `./scripts/test.sh`，再运行 Dashboard、Popup、首次引导与启动窗口相关阶段 7 验收场景；双语进行一次真实 `.app` 视觉检查。

回滚时可恢复旧视图布局和主菜单组装；新增语言字段可由旧版本 JSON decoder 忽略，不需要数据库迁移。若资源打包失败，应阻止发布而不是回退为混合硬编码文案。

## Open Questions

无。语言模式、正常/异常信息规则和快捷键范围已由用户确认；窗口精确尺寸在实现阶段根据双语内容和最小可读性验证确定。
