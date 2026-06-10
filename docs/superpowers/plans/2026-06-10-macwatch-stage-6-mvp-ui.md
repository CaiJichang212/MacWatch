# MacWatch 阶段 6：MVP UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 MacWatch 用户可见的 MVP 闭环：菜单栏、Popup、Dashboard、详情页、设置页和兼容性状态均能基于当前采样与本次会话历史正确展示。

**Architecture:** 阶段 6 只在 `MacWatchApp` 增加展示、设置持久化和 AppKit/SwiftUI 场景编排；`MacWatchCore` 只补必要的设置领域模型与轻量 SettingsStore，不新增采集能力。UI 通过 `MacWatchRuntime`、`LiveTemperatureState`、`SessionHistoryRepository` 和 `SettingsStore` 获取数据，不直接访问 IOKit、SMC、IOReport、DiskArbitration、SQLite、网络或 `Vendor/Stats`。实施顺序继续遵循 CPU 纵切优先：先让 CPU 从采集到菜单栏、Popup、Dashboard、详情趋势和设置单位完整可用，再横向补齐 GPU、内存、SSD/NAND、电池和系统温度。

**Tech Stack:** Swift Package Manager, Swift 5.9, macOS 13+, SwiftUI, AppKit `NSStatusItem`/`NSPopover`, Swift Charts, XCTest, MacWatchCore, MacWatchApp, StatsAdapter 只读 probe 链路。

---

## 代码片段控制规则

本计划遵循本次任务对 `superpowers:writing-plans` 的最新规定：计划文档写清目标、架构、文件路径、接口契约、测试与验收；只在关键、易误解、强约束处放小段接口签名、关键数据结构、测试样例、状态映射和伪代码。整文件级业务逻辑、完整 SwiftUI 组件实现、普通 CRUD、重复样板和可由测试与接口自然推导出的代码，进入执行阶段的代码仓库和 PR，不在本计划中展开。

## 需求来源

- `docs/origin/MacWatch_MVP版需求文档.md`：第 5、6、7、8、12 节定义 MVP 指标、状态、数据来源、页面需求和验收标准。
- `docs/origin/MacWatch_技术架构文档.md`：第 7、10、16 节定义 UI 场景结构、展示层访问规则、隐私安全和 MVP 验收。
- `docs/origin/Stats_功能梳理_事实版.md`：Stats 有菜单栏 Widget、Popup 和设置结构，但耦合 Module/Reader/Store/DB/Remote，不作为 MacWatch UI 复用对象。
- `docs/origin/Stats复用策略.md`：`Vendor/Stats` 只读参考，阶段 6 不修改、不接入 Stats UI、通知、Widget、DB、Remote、Updater 或联网能力。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-4-sampling-live-state-low-power.md`：已有调度、实时状态、stale、能力检测和历史写入链路。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-5-session-history-trends.md`：已有 SQLite 本次会话历史、范围查询、统计和按缺口断线趋势。

## 当前代码基线

当前仓库已经具备：

- `Sources/MacWatchApp/MacWatchApp.swift`：`WindowGroup(id: "main")` 和 SwiftUI `Settings` scene。
- `Sources/MacWatchApp/AppDelegate.swift`：创建 `MenuBarController`、启动 `MacWatchRuntime`，并把 live state 变化推给菜单栏。
- `Sources/MacWatchApp/MenuBar/MenuBarController.swift`：当前只用 `NSMenu` 展示 CPU 状态和打开设置/主窗口命令，尚无 SwiftUI Popup、菜单栏显示项配置、单位切换或 stale 弱化。
- `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift`：已持有 `SessionHistoryRepository`、调度器、`LiveTemperatureState`、`series(...)` 查询和 `clearCurrentSessionHistory()`。
- `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`：已有最高温、五类指标卡、1 小时趋势和嵌入详情雏形；缺少系统温度、不可用汇总、单位设置、来源/更新时间完整展示和清晰导航。
- `Sources/MacWatchApp/Views/TemperatureDetailView.swift`：已有范围选择和统计雏形；缺少单位设置、来源、采样状态、采样间隔、悬停读数和 Dashboard 选择联动完善。
- `Sources/MacWatchApp/Views/SettingsView.swift`：只有启动主窗口和清除历史；缺少温度单位、刷新间隔、默认趋势范围、菜单栏显示项和兼容性状态。
- `Sources/MacWatchCore/Settings/AppSettings.swift`：只有 `launchMainWindowOnStart`，需要扩展为 MVP 设置模型。
- `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`：已有基础格式化、Dashboard snapshot、详情统计和趋势断线测试，可继续扩展。

## 阶段 6 范围

包含：

- 菜单栏默认显示当前最高温，例如 `72°C`；支持最高温、CPU、GPU、内存、磁盘、电池显示项；支持摄氏度/华氏度；stale 状态弱化显示。
- 菜单栏点击打开 SwiftUI Popup，而不是只打开传统菜单。
- Popup 显示最高温、CPU、GPU、内存、SSD/NAND、电池、系统温度；每项展示状态、来源、更新时间；提供打开 Dashboard 和兼容性信息入口。
- Dashboard 显示最高温卡片、各温度指标卡片、最近 1 小时趋势摘要、可用数量和不可用指标说明；支持进入单指标详情。
- 详情页显示单指标趋势图，支持 15 分钟、1 小时、6 小时、全会话；显示当前值、最高、最低、平均、峰值时间、来源、采样状态和采样间隔；支持曲线悬停查看时间点数值。
- 设置页支持温度单位、刷新间隔、默认趋势范围、菜单栏显示项、兼容性状态和清除当前会话历史。
- 设置修改即时影响 UI 展示；刷新间隔按安全下限即时应用到调度器，若执行阶段发现当前调度器不适合热更新，则必须在 UI 明确显示“重启后生效”并在验收记录中说明。
- 先完成 CPU 温度 UI 纵切，再扩展 GPU、内存、SSD/NAND、电池和系统温度展示。

不包含：

- 不新增资源监控、进程统计、告警、导出、云同步、远程监控、Widget、风扇控制、长期跨会话历史或外部磁盘监控。
- 不修改 `Vendor/Stats`。
- 不复用 Stats `Reader`、`Module`、`DB.shared`、LevelDB、Remote、SystemStats、Updater、通知、LaunchAtLogin helper、privileged helper 或 SMC 写操作。
- 不把 `unsupported`、`readFailed`、`stale` 或无值状态显示成 `0°C`、空白、旧值或估算值。
- 不在 UI 层直接访问系统采集 API、SQLite、网络或 `Vendor/Stats`。

## 目标文件结构

```text
Sources/
  MacWatchCore/
    Settings/
      AppSettings.swift                         # 修改：补齐单位、刷新间隔、默认趋势范围、菜单栏显示项
      SettingsStore.swift                       # 新增：设置读写协议
      UserDefaultsSettingsStore.swift           # 新增：UserDefaults 持久化，隐藏 key/schema
  MacWatchApp/
    Runtime/
      MacWatchRuntime.swift                     # 修改：发布 settings、应用刷新间隔、提供 compatibility snapshot 输入
    MenuBar/
      MenuBarController.swift                   # 修改：NSStatusItem + NSPopover，标题按设置格式化
      MenuBarCommandHandler.swift               # 修改：增加打开兼容性入口或保留命令转发
      MenuBarPopupView.swift                    # 新增：SwiftUI Popup 内容
    Presentation/
      TemperatureMetricCatalog.swift            # 新增：MVP 指标清单、标题、metricName、展示顺序
      TemperatureFormatting.swift               # 新增：摄氏/华氏、状态、更新时间和来源格式化
      TemperatureOverviewSnapshot.swift         # 新增：Dashboard/Popup 共用概览 snapshot
      CompatibilitySnapshot.swift               # 新增：兼容性状态和不可用原因汇总
    Views/
      ContentView.swift                         # 修改：Dashboard/详情导航结构
      TemperatureDashboardView.swift            # 修改：MVP Dashboard 总览
      TemperatureDetailView.swift               # 修改：完整详情页和悬停读数
      TemperatureTrendView.swift                # 修改：单位坐标、悬停、gap 说明
      SettingsView.swift                        # 修改：MVP 设置表单和清除历史确认
      CompatibilityView.swift                   # 新增：兼容性信息页面/面板
Tests/
  MacWatchCoreTests/
    AppSettingsTests.swift                      # 修改：默认值、Codable/UserDefaults round trip
    UserDefaultsSettingsStoreTests.swift        # 新增：持久化和损坏值回退
  MacWatchAppTests/
    TemperaturePresentationTests.swift          # 修改：单位、状态、overview、compatibility、detail snapshot
    MenuBarControllerTests.swift                # 新增或扩展：标题选择和 30 字符约束的纯逻辑测试
    MacWatchRuntimeSettingsTests.swift          # 新增：设置变更发布、刷新间隔契约
```

## 接口契约

### 设置模型

`AppSettings` 属于 Core，可被 Runtime、Settings UI、菜单栏和测试共同使用。温度值在 Core 历史和 sample 中仍统一保存摄氏度；单位转换只在 `MacWatchApp` 展示层发生。

```swift
public enum TemperatureUnit: String, CaseIterable, Codable, Sendable {
    case celsius
    case fahrenheit
}

public enum RefreshInterval: TimeInterval, CaseIterable, Codable, Sendable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
}

public enum MenuBarDisplayMetric: String, CaseIterable, Codable, Sendable {
    case hottest
    case cpu
    case gpu
    case memory
    case ssd
    case battery
}
```

默认值：

| Setting | Default |
| --- | --- |
| `temperatureUnit` | `.celsius` |
| `refreshInterval` | `.fiveSeconds` |
| `defaultTrendRange` | `.oneHour` |
| `menuBarDisplayMetric` | `.hottest` |
| `launchMainWindowOnStart` | `true` |

强约束：

- `RefreshInterval` 只暴露 5 秒、10 秒、30 秒三个选项。
- 菜单栏显示项不包含 `system` 和 `sensor`，符合需求中的最高温、CPU、GPU、内存、磁盘、电池。
- 默认趋势范围使用阶段 5 的 `TemperatureHistoryRange`，不得新增自由时间输入。
- 设置损坏或缺失时回退默认值，并保留当前会话历史；重置设置不得清除历史。

### SettingsStore

`SettingsStore` 隐藏持久化细节，当前实现用 UserDefaults；UI 只通过 `MacWatchRuntime` 或显式注入的 store 访问，不在 View 内散落 `@AppStorage` key。

```swift
public protocol SettingsStore: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}
```

UserDefaults key 必须带 MacWatch 命名空间，例如 `MacWatch.settings.v1`。执行阶段如果采用 JSON 编码保存整个 `AppSettings`，测试需要覆盖未知 enum rawValue 回退默认值。

### MVP 指标目录

所有 UI surface 使用同一个目录，避免 Popup、Dashboard、详情页和兼容性页展示顺序或 metricName 不一致。

```swift
struct TemperatureMetricDescriptor: Identifiable, Equatable {
    let id: TemperatureDomain
    let domain: TemperatureDomain
    let metricName: String
    let title: String
    let menuBarMetric: MenuBarDisplayMetric?
    let isMVPCompatibilityRequired: Bool
}
```

展示顺序：

1. Hottest
2. CPU
3. GPU
4. Memory
5. SSD/NAND
6. Battery
7. System

系统温度进入 Popup、Dashboard 和详情，但不进入菜单栏显示项设置。CPU、GPU、内存、SSD/NAND、电池必须始终出现在兼容性信息中；不可读时显示 `unsupported` 或 `readFailed` 原因，不能消失。

### 温度格式化

状态和值格式化集中在 `TemperatureFormatting.swift`，避免各 View 自己拼接状态。

关键规则：

| Sample state | 当前值展示 | 状态展示 | 参与最高温 |
| --- | --- | --- | --- |
| `valid + valueCelsius` | `72°C` 或 `162°F` | `valid` | 是 |
| `unsupported` | `--` | `unsupported` + reason | 否 |
| `readFailed` | `--` | `readFailed` + reason | 否 |
| `stale` | `72°C` 可作为“最近有效值”弱化展示，必须标记 stale | `stale` + last updated | 否 |
| no sample | `--` | `waiting` 或 capability reason | 否 |

stale 菜单栏标题建议：

```swift
// 例：不显示成正常实时值；实际 UI 可用 disabled/secondary style 或前缀符号。
TemperatureDisplayText(value: "72°C", statusSuffix: "stale", isStale: true)
```

强约束：

- 菜单栏最终可见文本不超过 30 个字符。
- Fahrenheit 公式为 `valueCelsius * 9 / 5 + 32`，四舍五入到整数。
- `unsupported`、`readFailed`、无 sample 不显示 `0°C`。
- `stale` 可以显示最近有效值，但必须弱化且明确标记 stale；不能让用户以为它是实时值。

### Runtime 设置应用

`MacWatchRuntime` 作为 App 组合根发布设置并驱动菜单栏和 SwiftUI 刷新。

```swift
@Published private(set) var settings: AppSettings

func updateSettings(_ transform: (inout AppSettings) -> Void)
func applyRefreshInterval(_ interval: RefreshInterval)
```

执行阶段优先实现即时刷新间隔应用：

- `RefreshInterval.fiveSeconds`：CPU/GPU 实时 5 秒，慢域仍受阶段 4 minimum interval 限制。
- `RefreshInterval.tenSeconds`：CPU/GPU 实时 10 秒，慢域不低于 30 秒。
- `RefreshInterval.thirtySeconds`：所有实时读取可放慢到安全范围内。

若当前 `TemperatureScheduler` 无法无风险热更新 policy，则执行阶段必须采用保守策略：

- 设置保存立即影响单位、菜单栏显示项和默认趋势范围。
- 刷新间隔在设置页显示“重启后生效”。
- 验收记录明确该项未即时生效，并作为阶段 7/后续技术债处理。

## 实施任务

### Task 1: 设置模型与持久化

**Files:**
- Modify: `Sources/MacWatchCore/Settings/AppSettings.swift`
- Create: `Sources/MacWatchCore/Settings/SettingsStore.swift`
- Create: `Sources/MacWatchCore/Settings/UserDefaultsSettingsStore.swift`
- Modify: `Tests/MacWatchCoreTests/AppSettingsTests.swift`
- Create: `Tests/MacWatchCoreTests/UserDefaultsSettingsStoreTests.swift`

- [ ] **Step 1: 写设置默认值测试**

测试覆盖默认单位、刷新间隔、默认趋势范围、菜单栏显示项和不清除历史的重置语义。关键断言：

```swift
XCTAssertEqual(AppSettings.default.temperatureUnit, .celsius)
XCTAssertEqual(AppSettings.default.refreshInterval, .fiveSeconds)
XCTAssertEqual(AppSettings.default.defaultTrendRange, .oneHour)
XCTAssertEqual(AppSettings.default.menuBarDisplayMetric, .hottest)
XCTAssertTrue(AppSettings.default.launchMainWindowOnStart)
```

- [ ] **Step 2: 运行 Core 设置测试并确认失败**

Run: `swift test --filter AppSettingsTests`

Expected: 新增属性或类型尚未实现导致编译失败。

- [ ] **Step 3: 扩展设置模型和 store**

实现 `TemperatureUnit`、`RefreshInterval`、`MenuBarDisplayMetric`、扩展后的 `AppSettings`，并新增 `SettingsStore` 与 `UserDefaultsSettingsStore`。只保存设置，不触碰 session history repository。

- [ ] **Step 4: 写 UserDefaults round-trip 和损坏值回退测试**

用 isolated suite name 创建 `UserDefaults`，验证保存后可读取，损坏 payload 或未知 enum 时回退 `.default`。

- [ ] **Step 5: 运行设置测试**

Run: `swift test --filter AppSettingsTests && swift test --filter UserDefaultsSettingsStoreTests`

Expected: PASS。

### Task 2: 展示目录与格式化纯逻辑

**Files:**
- Create: `Sources/MacWatchApp/Presentation/TemperatureMetricCatalog.swift`
- Create: `Sources/MacWatchApp/Presentation/TemperatureFormatting.swift`
- Modify: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`

- [ ] **Step 1: 写单位和菜单栏标题测试**

测试 Celsius/Fahrenheit、非 valid 状态、stale 标记和 30 字符约束。关键样例：

```swift
XCTAssertEqual(TemperatureFormatter.text(celsius: 72.4, unit: .celsius), "72°C")
XCTAssertEqual(TemperatureFormatter.text(celsius: 72.4, unit: .fahrenheit), "162°F")
XCTAssertLessThanOrEqual(MenuBarTitleFormatter.title(for: snapshot).count, 30)
```

- [ ] **Step 2: 写 MVP 指标目录测试**

断言目录包含 CPU、GPU、内存、SSD/NAND、电池、System，且 CPU/GPU/内存/SSD/电池 `isMVPCompatibilityRequired == true`。

- [ ] **Step 3: 运行 App presentation 测试并确认失败**

Run: `swift test --filter TemperaturePresentationTests`

Expected: 新 presentation 类型不存在导致失败。

- [ ] **Step 4: 实现目录和格式化**

迁移 `TemperatureDashboardSnapshot.title(for:)` 和 `metricName(for:)` 的职责到 `TemperatureMetricCatalog`，保留旧入口或逐步迁移调用点，避免一次性大改。

- [ ] **Step 5: 运行 presentation 测试**

Run: `swift test --filter TemperaturePresentationTests`

Expected: PASS。

### Task 3: Runtime 接入 SettingsStore 与设置发布

**Files:**
- Modify: `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift`
- Modify: `Sources/MacWatchApp/AppDelegate.swift`
- Create: `Tests/MacWatchAppTests/MacWatchRuntimeSettingsTests.swift`

- [ ] **Step 1: 写 runtime 设置发布测试**

测试 `MacWatchRuntime` 初始化时加载 store 设置，`updateSettings` 保存并发布变更。

- [ ] **Step 2: 写刷新间隔契约测试**

如果实现即时热更新，测试 `applyRefreshInterval(.tenSeconds)` 后 CPU/GPU policy 变慢且慢域不低于 minimum interval。若采用重启后生效策略，测试 runtime 暴露明确状态给 Settings UI。

- [ ] **Step 3: 运行 runtime 设置测试并确认失败**

Run: `swift test --filter MacWatchRuntimeSettingsTests`

Expected: 设置 API 不存在导致失败。

- [ ] **Step 4: 实现 runtime 设置组合**

给 `MacWatchRuntime` 注入 `SettingsStore`，发布 `settings`，实现 `updateSettings`。同时把 `MacWatchSharedDependencies` 扩展为创建默认 UserDefaults store。

- [ ] **Step 5: 运行 Runtime 相关测试**

Run: `swift test --filter MacWatchRuntimeSettingsTests && swift test --filter MacWatchRuntimeSchedulerTests`

Expected: PASS；已有采样启动测试不回退。

### Task 4: CPU UI 纵切

**Files:**
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarController.swift`
- Create: `Sources/MacWatchApp/MenuBar/MenuBarPopupView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureDetailView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureTrendView.swift`
- Modify: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`

- [ ] **Step 1: 写 CPU snapshot 测试**

构造只有 CPU valid 的 `LiveTemperatureState`，断言菜单栏显示最高温、Popup row、Dashboard CPU 卡片和详情统计均使用同一 formatter。

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter TemperaturePresentationTests`

Expected: Popup/overview snapshot 尚不存在或字段缺失。

- [ ] **Step 3: 实现 CPU 从 live state 到 UI 的最小纵切**

菜单栏标题使用 `settings.menuBarDisplayMetric == .hottest` 的 CPU 最高温；Popup 至少显示 Hottest 和 CPU；Dashboard 显示最高温卡片、CPU 卡片和 1 小时 CPU 趋势；详情页默认范围来自 `settings.defaultTrendRange`。

- [ ] **Step 4: 运行 CPU UI 纵切测试**

Run: `swift test --filter TemperaturePresentationTests`

Expected: PASS。

- [ ] **Step 5: 本地启动检查 CPU 路径**

Run: `swift run MacWatchApp`

Expected: App 启动显示菜单栏图标；在无法真实验证硬件温度的环境中，至少确认无启动崩溃。真实 MacBook Air M4 验收需要看到 CPU `valid` 温度。

### Task 5: 菜单栏与 Popup 完整化

**Files:**
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarController.swift`
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarCommandHandler.swift`
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarPopupView.swift`
- Modify: `Tests/MacWatchAppTests/MenuBarCommandHandlerTests.swift`
- Create or Modify: `Tests/MacWatchAppTests/MenuBarControllerTests.swift`

- [ ] **Step 1: 写菜单栏显示项测试**

覆盖 `.hottest`、`.cpu`、`.gpu`、`.memory`、`.ssd`、`.battery`，并验证不可用显示为 `--` 或明确状态，不显示 `0°C`。

- [ ] **Step 2: 写 Popup row 测试**

测试 Popup snapshot 包含 Hottest、CPU、GPU、Memory、SSD/NAND、Battery、System；每项有 value/status/source/updatedAt/reason。

- [ ] **Step 3: 运行菜单栏测试并确认失败**

Run: `swift test --filter MenuBar`

Expected: 新 popup/title 逻辑尚未实现导致失败。

- [ ] **Step 4: 用 NSPopover 替换点击菜单行为**

`NSStatusItem` 左键点击切换 `NSPopover`，Popover root 为 `MenuBarPopupView().environmentObject(runtime)` 或等价注入。保留打开 Dashboard、Settings、Quit 的明确按钮/命令入口。

- [ ] **Step 5: 实现 Popup 动作入口**

Popup 内提供：

- `Open Dashboard`：打开 `WindowGroup(id: "main")` 并激活 App。
- `Compatibility`：打开主窗口并定位兼容性页面，或打开兼容性 sheet/panel。
- `Settings`：调用 `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` 或既有设置打开动作。

- [ ] **Step 6: 运行菜单栏测试**

Run: `swift test --filter MenuBar && swift test --filter TemperaturePresentationTests`

Expected: PASS。

### Task 6: Dashboard 总览完整化

**Files:**
- Modify: `Sources/MacWatchApp/Views/ContentView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`
- Create: `Sources/MacWatchApp/Presentation/TemperatureOverviewSnapshot.swift`
- Create: `Sources/MacWatchApp/Presentation/CompatibilitySnapshot.swift`
- Create: `Sources/MacWatchApp/Views/CompatibilityView.swift`
- Modify: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`

- [ ] **Step 1: 写 Dashboard overview 测试**

测试 Dashboard snapshot 包含最高温、6 个指标卡片、最近 1 小时趋势摘要、可用数量、不可用指标说明。不可用 GPU/内存/SSD/电池必须显示原因。

- [ ] **Step 2: 运行 Dashboard 测试并确认失败**

Run: `swift test --filter TemperaturePresentationTests`

Expected: overview/compatibility 字段缺失。

- [ ] **Step 3: 实现 Dashboard 展示**

使用 `NavigationSplitView` 或清晰的 sidebar-detail 结构；Dashboard 首屏保留最高温、指标卡片和最近 1 小时趋势摘要。指标卡片显示单位、更新时间、来源、状态；点击卡片进入详情。

- [ ] **Step 4: 实现不可用说明和兼容性入口**

不可用说明使用 `CompatibilitySnapshot` 生成，按 CPU/GPU/Memory/SSD/NAND/Battery/System 顺序展示状态、source、reasonCode、rawKey。不要隐藏 unsupported/readFailed 指标。

- [ ] **Step 5: 运行 Dashboard 测试**

Run: `swift test --filter TemperaturePresentationTests`

Expected: PASS。

### Task 7: 详情页和趋势交互

**Files:**
- Modify: `Sources/MacWatchApp/Views/TemperatureDetailView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureTrendView.swift`
- Modify: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`

- [ ] **Step 1: 写详情 snapshot 测试**

测试当前值、最大、最小、平均、峰值时间、source、sampling status、采样间隔文本和单位转换。

- [ ] **Step 2: 写趋势缺口和 hover 纯逻辑测试**

继续使用 `TemperatureTrendSegments.segments(for:)` 验证 gap 不跨线；新增 nearest point helper 测试，用固定时间命中最近样本。

伪代码边界：

```swift
nearestSample = validSamples.min(by: abs(sample.timestamp - hoverTimestamp))
return nil when validSamples.isEmpty
```

- [ ] **Step 3: 运行详情趋势测试并确认失败**

Run: `swift test --filter TemperaturePresentationTests`

Expected: 新字段或 hover helper 尚未实现。

- [ ] **Step 4: 实现详情页**

详情页范围 Picker 支持 `.fifteenMinutes`、`.oneHour`、`.sixHours`、`.allSession`，默认取 `settings.defaultTrendRange`。趋势图 y 轴按设置单位展示，gap 文案明确 sleep/read failure/stale/history write failure 可能导致断线。

- [ ] **Step 5: 实现 Chart hover**

使用 `chartOverlay` 或等价 Swift Charts 能力读取鼠标位置，展示最近有效样本的时间和值。无有效样本时不显示 hover 值，不伪造数据点。

- [ ] **Step 6: 运行详情趋势测试**

Run: `swift test --filter TemperaturePresentationTests`

Expected: PASS。

### Task 8: 设置页完整化

**Files:**
- Modify: `Sources/MacWatchApp/Views/SettingsView.swift`
- Modify: `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift`
- Modify: `Tests/MacWatchAppTests/MacWatchRuntimeSettingsTests.swift`
- Modify: `Tests/MacWatchCoreTests/AppSettingsTests.swift`

- [ ] **Step 1: 写设置表单契约测试**

测试设置修改调用 `runtime.updateSettings` 后保存并反映到 `runtime.settings`；清除历史只调用 `clearCurrentSessionHistory()`，不重置 settings。

- [ ] **Step 2: 运行设置相关测试并确认失败**

Run: `swift test --filter MacWatchRuntimeSettingsTests && swift test --filter AppSettingsTests`

Expected: SettingsView/runtime 绑定尚未完成。

- [ ] **Step 3: 实现 SettingsView 表单**

设置页包含：

- 温度单位 Picker：Celsius/Fahrenheit。
- 刷新间隔 Picker：5s/10s/30s。
- 默认趋势范围 Picker：15m/1h/6h/Session。
- 菜单栏显示项 Picker：Hottest/CPU/GPU/Memory/SSD/NAND/Battery。
- 兼容性状态：嵌入 `CompatibilityView` 的紧凑版本。
- 清除当前会话历史：destructive button + 二次确认。

- [ ] **Step 4: 确认设置即时生效路径**

单位、菜单栏显示项、默认趋势范围必须即时生效。刷新间隔按 Task 3 的实现路径即时生效或显示重启提示，不允许静默不生效。

- [ ] **Step 5: 运行设置测试**

Run: `swift test --filter MacWatchRuntimeSettingsTests && swift test --filter AppSettingsTests`

Expected: PASS。

### Task 9: 横向补齐 GPU/内存/SSD/电池/System UI

**Files:**
- Modify: `Sources/MacWatchApp/Presentation/TemperatureMetricCatalog.swift`
- Modify: `Sources/MacWatchApp/Presentation/TemperatureOverviewSnapshot.swift`
- Modify: `Sources/MacWatchApp/Presentation/CompatibilitySnapshot.swift`
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarPopupView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureDetailView.swift`
- Modify: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`

- [ ] **Step 1: 写横向指标测试矩阵**

为 GPU、内存、SSD/NAND、电池各构造 valid、unsupported、readFailed、stale 样本或 capability。断言：

- valid 显示温度、单位、source、updatedAt。
- unsupported/readFailed 显示原因，不参与最高温。
- stale 弱化并显示 stale，不当作正常实时值。
- System 在 Popup/Dashboard/详情可见，但不进入菜单栏设置项。

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter TemperaturePresentationTests`

Expected: 部分横向状态尚未完整展示。

- [ ] **Step 3: 补齐各指标 UI 绑定**

把所有 UI surface 切换到 `TemperatureMetricCatalog` 和 `TemperatureOverviewSnapshot`，移除散落的硬编码 title/metricName 逻辑。

- [ ] **Step 4: 运行横向指标测试**

Run: `swift test --filter TemperaturePresentationTests`

Expected: PASS。

### Task 10: 集成验证与验收记录

**Files:**
- Modify: `docs/superpowers/plans/2026-06-10-macwatch-stage-6-mvp-ui.md` only if execution notes are appended by implementer
- Optional Create: `docs/validation/stage-6-mvp-ui-validation.md`

- [ ] **Step 1: 跑完整自动化测试**

Run: `swift test`

Expected: PASS。

- [ ] **Step 2: 运行一次探针诊断**

Run: `swift run MacWatchApp --probe-temperature-once`

Expected: 输出 JSON lines；在 MacBook Air M4 验收机上至少 CPU 相关结果应包含一个有效温度或能明确定位读取失败原因。

- [ ] **Step 3: 启动 App 做手工 UI 验收**

Run: `swift run MacWatchApp`

检查：

- 菜单栏默认显示最高温，文本不超过 30 字符。
- 点击菜单栏打开 Popup，1 秒内显示最近状态。
- Popup 有 Dashboard 和 Compatibility 入口。
- Dashboard 首屏包含最高温、指标卡、1 小时趋势摘要和不可用说明。
- 详情页 15m/1h/6h/Session 范围可切换，gap 不跨线。
- 设置页修改单位、菜单栏显示项、默认趋势范围立即反映到 UI。
- 清除当前会话历史有二次确认，清除后趋势为空或重新从后续样本开始。

- [ ] **Step 4: 性能和主线程粗验收**

手工记录 Dashboard 首屏打开和当前会话趋势查询是否小于 1 秒；菜单栏、Popup、Dashboard 打开不能出现明显主线程卡顿。若发现卡顿，优先检查趋势查询是否在 View body 中重复执行，应缓存 snapshot 或通过 runtime publish revision 限流。

- [ ] **Step 5: 记录真实硬件未验证项**

如果当前环境不是 MacBook Air M4 或无法读取真实温度，在验收记录中明确写出：自动化测试已覆盖 fake probe/presentation/history 查询；真实 CPU 温度、GPU/内存/SSD/电池硬件支持状态仍需在 MacBook Air M4 上验证。

## 验收标准

自动化验收：

- `swift test` 全部通过。
- 设置模型默认值、UserDefaults 持久化和损坏值回退有测试覆盖。
- 菜单栏标题选择、单位转换、stale/unsupported/readFailed 状态和 30 字符约束有测试覆盖。
- Popup/Dashboard/详情/兼容性 snapshot 对 CPU、GPU、内存、SSD/NAND、电池、System 的展示顺序、状态、来源、更新时间和原因有测试覆盖。
- 趋势图分段逻辑继续保证 gap 不跨线。

手工验收：

- 菜单栏默认显示最高温，支持用户选择最高温、CPU、GPU、内存、磁盘、电池。
- Popup 打开后 1 秒内展示最近一次采样状态。
- Dashboard 首屏小于 1 秒，趋势查询小于 1 秒。
- 详情页支持 15 分钟、1 小时、6 小时、全会话，显示当前值、最高、最低、平均、峰值时间、来源和采样状态。
- 设置修改即时生效，或刷新间隔明确提示重启后生效。
- MacBook Air M4 验收机上必须读到并展示至少一个 `valid` CPU 温度。
- 不支持的 GPU/内存/SSD/NAND/电池指标显示 `unsupported` 或 `readFailed`，不显示伪造值，也不能从兼容性信息中消失。

隐私与边界验收：

- 阶段 6 不新增任何网络访问。
- 阶段 6 不修改 `Vendor/Stats`。
- UI 不直接访问 IOKit、SMC、IOReport、DiskArbitration、SQLite 或 `Vendor/Stats`。
- 无风扇 MacBook Air 不显示风扇功能。
- 不引入 privileged helper、SMC 写操作、告警、导出、Widget、云同步、远程监控或长期跨会话历史。

## 实施顺序与提交建议

建议按任务顺序提交，保持每个提交可测试：

1. `feat: add mvp settings model`
2. `feat: add temperature presentation catalog`
3. `feat: publish settings from runtime`
4. `feat: complete cpu ui vertical slice`
5. `feat: add menu bar popup`
6. `feat: complete dashboard overview`
7. `feat: complete temperature detail view`
8. `feat: complete mvp settings view`
9. `feat: cover remaining temperature domains in ui`
10. `test: record stage 6 validation`

## 自检清单

- [ ] 计划覆盖菜单栏、Popup、Dashboard、详情页、设置页和兼容性状态。
- [ ] 计划明确 CPU 纵切优先，再横向补齐 GPU/内存/SSD/电池。
- [ ] 计划没有要求修改 `Vendor/Stats`。
- [ ] 计划没有引入 Post-MVP 功能。
- [ ] 计划中的代码片段只包含接口签名、关键规则和测试样例，没有整文件实现。
- [ ] 所有新增/修改文件路径都位于 `Sources/MacWatchCore`、`Sources/MacWatchApp`、`Tests` 或 `docs` 的合理目录。
- [ ] 测试和验收同时覆盖自动化、手工 UI、真实硬件未验证项和隐私边界。
