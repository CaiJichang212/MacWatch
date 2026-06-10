# MacWatch 阶段 1：工程骨架与边界确认 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可编译、可运行、职责清晰的 macOS App 基础，为后续 CPU 温度端到端纵切提供稳定工程骨架。

**Architecture:** 第一阶段只搭建 SwiftPM 工程、macOS App 场景、App 生命周期入口、测试与边界检查，不实现真实温度采集。`MacWatchApp` 只依赖 `MacWatchCore` 和 `StatsAdapter` 的公开契约；`MacWatchCore` 不依赖 AppKit/SwiftUI；`StatsAdapter` 只作为未来只读采集适配层，禁止接入 Stats `Reader`、`DB.shared`、Remote、Updater、通知或 helper。

**Tech Stack:** Swift Package Manager, Swift, SwiftUI, AppKit `NSStatusItem`, XCTest, shell scripts, macOS 12+.

---

## 代码片段控制规则

本计划遵循本次任务对 `superpowers:writing-plans` 的最新规定：文档写清目标、架构、文件路径、接口契约、测试与验收；只在关键、易误解、强约束处放小段接口签名、schema 摘要或测试样例。整文件级实现、普通样板代码和完整组件实现应在执行阶段进入代码仓库和 PR，不在计划文档中展开。

## 需求来源

- `docs/origin/MacWatch-MVP-7阶段开发任务.md`：阶段 1 目标与任务。
- `docs/origin/MacWatch_技术架构文档.md`：分层、Stats 边界、UI 场景结构、目录建议和验收标准。
- `docs/origin/MacWatch_MVP版需求文档.md`：MVP 范围、目标机型、不可读状态和隐私边界。
- `docs/origin/Stats复用策略.md`：`Vendor/Stats` 只读上游引用、固定版本 `v3.0.1`、通过 `StatsAdapter` 隔离。

## 阶段 1 范围

阶段 1 包含：

- 创建 Swift/macOS 工程入口：`Package.swift`、`MacWatchApp` executable target、`MacWatchCore` library target、`StatsAdapter` library target。
- 创建 macOS 场景结构：AppKit `NSStatusItem` 菜单栏入口、SwiftUI `WindowGroup` 主窗口、SwiftUI `Settings` scene。
- 创建 App 生命周期入口：启动、退出、睡眠、唤醒事件可观测并可测试。
- 创建 Stats 只读边界：文档、适配层空壳、静态扫描脚本。
- 创建单元测试和构建脚本：后续每个阶段可通过 `swift build`、`swift test` 和边界扫描验证。

阶段 1 不包含：

- 不实现 CPU/GPU/内存/SSD/电池真实温度读取。
- 不移植 Stats HID/SMC/Battery/NVMe 读取逻辑。
- 不创建 SQLite 会话历史表。
- 不实现趋势图、Dashboard 完整 UI、Popup 完整温度列表。
- 不接入网络、通知、LaunchAtLogin helper、SMC privileged helper 或风扇控制。

## 目标文件结构

```text
MacWatch/
  Package.swift
  Sources/
    MacWatchApp/
      MacWatchApp.swift
      AppDelegate.swift
      MenuBar/
        MenuBarController.swift
      Views/
        ContentView.swift
        SettingsView.swift
    MacWatchCore/
      Lifecycle/
        AppLifecycleCoordinator.swift
        AppLifecycleEvent.swift
      Settings/
        AppSettings.swift
    StatsAdapter/
      StatsAdapterBoundary.swift
      StatsReadOnlySource.swift
  Tests/
    MacWatchCoreTests/
      AppLifecycleCoordinatorTests.swift
      AppSettingsTests.swift
    StatsAdapterTests/
      StatsAdapterBoundaryTests.swift
  scripts/
    build.sh
    test.sh
    run.sh
    verify_stats_boundary.sh
  script/
    build_and_run.sh
  .codex/
    environments/
      environment.toml
  docs/
    architecture/
      stats-boundary.md
```

## 接口契约

### SwiftPM target 契约

`Package.swift` 必须声明：

- executable target：`MacWatchApp`
- library target：`MacWatchCore`
- library target：`StatsAdapter`
- test target：`MacWatchCoreTests`
- test target：`StatsAdapterTests`

目标依赖方向：

```text
MacWatchApp -> MacWatchCore
MacWatchApp -> StatsAdapter
StatsAdapter -> MacWatchCore
MacWatchCore -> no local target dependency
```

禁止依赖方向：

```text
MacWatchCore -> MacWatchApp
MacWatchCore -> StatsAdapter
StatsAdapter -> MacWatchApp
```

### App 生命周期契约

第一阶段只要求事件入口稳定，不要求启动采样。核心层生命周期事件保持纯 Swift、可单测：

```swift
public enum AppLifecycleEvent: Equatable, Sendable {
    case launched
    case willSleep
    case didWake
    case willTerminate
}

public protocol AppLifecycleEventSink: AnyObject {
    func record(_ event: AppLifecycleEvent)
}
```

`MacWatchApp` 负责把 AppKit 系统通知转换为上述事件；`MacWatchCore` 只记录和分发事件，不直接 import AppKit。

### Settings 契约

第一阶段只放后续阶段需要的最小设置占位，避免 UI 硬编码：

```swift
public struct AppSettings: Equatable, Sendable {
    public var launchMainWindowOnStart: Bool
}
```

温度单位、刷新间隔、趋势范围和菜单栏显示项在后续阶段扩展，不在阶段 1 中提前实现业务逻辑。

### StatsAdapter 边界契约

`StatsAdapter` 第一阶段只暴露边界说明和可编译空壳，不读取真实传感器：

```swift
public enum StatsReadOnlySource: String, CaseIterable, Sendable {
    case hidSensors
    case smcReadOnly
    case batteryIORegistry
    case nvmeSMART
}
```

强约束：

- `StatsAdapter` 不得 import SwiftUI。
- `StatsAdapter` 不得写数据库。
- `StatsAdapter` 不得发通知。
- `StatsAdapter` 不得访问网络。
- `StatsAdapter` 不得实例化 Stats `Reader` 或调用 Stats `DB.shared`。
- `Vendor/Stats` 只读引用，阶段 1 不修改其内容。

### macOS 场景契约

`MacWatchApp` 必须建立：

- `@main` SwiftUI App 入口。
- `@NSApplicationDelegateAdaptor(AppDelegate.self)`。
- `WindowGroup(id: "main")` 主窗口，承载 `ContentView`。
- `Settings` scene，承载 `SettingsView`。
- `MenuBarController` 持有 AppKit `NSStatusItem`，显示短文本，例如 `--°C` 或 `MacWatch`。

第一阶段主窗口和设置页只展示骨架状态，不展示伪造温度。

## 任务清单

### Task 1: 创建 SwiftPM 工程骨架

**Files:**

- Create: `Package.swift`
- Keep: `Sources/MacWatchApp/`
- Keep: `Sources/MacWatchCore/`
- Keep: `Sources/StatsAdapter/`
- Create: `Tests/MacWatchCoreTests/`
- Create: `Tests/StatsAdapterTests/`

- [ ] **Step 1: 写入 SwiftPM target 契约**

  `Package.swift` 只声明产品、targets、macOS 12 平台和依赖关系。关键约束是 `MacWatchCore` 不依赖任何本地 target，`StatsAdapter` 只依赖 `MacWatchCore`，`MacWatchApp` 依赖二者。

  关键摘要：

  ```swift
  products: [
      .executable(name: "MacWatchApp", targets: ["MacWatchApp"]),
      .library(name: "MacWatchCore", targets: ["MacWatchCore"]),
      .library(name: "StatsAdapter", targets: ["StatsAdapter"]),
  ]
  ```

- [ ] **Step 2: 创建最小可编译源文件**

  在三个 target 中分别创建一个最小公开类型或入口，保证 `swift build` 不因为空 target 失败。App target 的完整场景实现放到 Task 3。

- [ ] **Step 3: 运行构建验证**

  Run: `swift build`

  Expected: 构建成功，输出包含 `Build complete`。

- [ ] **Step 4: 提交**

  ```bash
  git add Package.swift Sources Tests
  git commit -m "chore: scaffold Swift package targets"
  ```

### Task 2: 建立 Core 生命周期与设置基础

**Files:**

- Create: `Sources/MacWatchCore/Lifecycle/AppLifecycleEvent.swift`
- Create: `Sources/MacWatchCore/Lifecycle/AppLifecycleCoordinator.swift`
- Create: `Sources/MacWatchCore/Settings/AppSettings.swift`
- Create: `Tests/MacWatchCoreTests/AppLifecycleCoordinatorTests.swift`
- Create: `Tests/MacWatchCoreTests/AppSettingsTests.swift`

- [ ] **Step 1: 先写生命周期测试**

  测试只验证事件记录顺序，不引入 AppKit：

  ```swift
  func testRecordsLifecycleEventsInOrder() {
      let coordinator = AppLifecycleCoordinator()
      coordinator.record(.launched)
      coordinator.record(.willSleep)
      coordinator.record(.didWake)
      XCTAssertEqual(coordinator.events, [.launched, .willSleep, .didWake])
  }
  ```

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter MacWatchCoreTests.AppLifecycleCoordinatorTests`

  Expected: 失败原因是 `AppLifecycleCoordinator` 或 `AppLifecycleEvent` 尚未定义。

- [ ] **Step 3: 实现最小 Core 类型**

  实现 `AppLifecycleEvent`、`AppLifecycleCoordinator`、`AppSettings`。`AppLifecycleCoordinator` 可用 `@MainActor` 或同步实现；第一阶段只需可测试、可注入，不启动定时器。

- [ ] **Step 4: 运行 Core 测试**

  Run: `swift test --filter MacWatchCoreTests`

  Expected: `MacWatchCoreTests` 全部通过。

- [ ] **Step 5: 提交**

  ```bash
  git add Sources/MacWatchCore Tests/MacWatchCoreTests
  git commit -m "feat: add core lifecycle foundation"
  ```

### Task 3: 建立 macOS App 场景结构

**Files:**

- Create: `Sources/MacWatchApp/MacWatchApp.swift`
- Create: `Sources/MacWatchApp/AppDelegate.swift`
- Create: `Sources/MacWatchApp/MenuBar/MenuBarController.swift`
- Create: `Sources/MacWatchApp/Views/ContentView.swift`
- Create: `Sources/MacWatchApp/Views/SettingsView.swift`

- [ ] **Step 1: 建立 AppKit + SwiftUI 场景边界**

  `MacWatchApp` 使用 SwiftUI `App` 生命周期，`AppDelegate` 负责 `NSStatusItem` 和系统通知桥接。不要使用 SwiftUI `MenuBarExtra` 替代 `NSStatusItem`，因为阶段 1 明确要求 `NSStatusItem` 菜单栏入口。

  关键结构摘要：

  ```swift
  @main
  struct MacWatchApp: App {
      @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

      var body: some Scene {
          WindowGroup(id: "main") { ContentView() }
          Settings { SettingsView() }
      }
  }
  ```

- [ ] **Step 2: 建立 `MenuBarController`**

  `MenuBarController` 持有 `NSStatusItem`，第一阶段只显示骨架文本和菜单项：

  - `Open MacWatch`
  - `Settings`
  - `Quit MacWatch`

  菜单项文字保持短文本；后续温度状态进入阶段 6。

- [ ] **Step 3: 桥接启动、退出、睡眠、唤醒通知**

  `AppDelegate` 在启动时记录 `.launched`，监听：

  - `NSApplication.willTerminateNotification` -> `.willTerminate`
  - `NSWorkspace.willSleepNotification` -> `.willSleep`
  - `NSWorkspace.didWakeNotification` -> `.didWake`

  事件只进入 `MacWatchCore.AppLifecycleCoordinator`，不启动采样。

- [ ] **Step 4: 运行 App 构建**

  Run: `swift build`

  Expected: 构建成功；不存在 `MacWatchCore` import `AppKit` 或 `SwiftUI` 的编译依赖。

- [ ] **Step 5: 手动运行冒烟检查**

  Run: `swift run MacWatchApp`

  Expected: 进程启动，菜单栏出现 `MacWatch` 或 `--°C` 状态项；主窗口可打开；Settings 可打开；退出菜单可结束进程。

- [ ] **Step 6: 提交**

  ```bash
  git add Sources/MacWatchApp
  git commit -m "feat: add macOS app scenes and menu bar entry"
  ```

### Task 4: 建立 StatsAdapter 只读边界

**Files:**

- Create: `Sources/StatsAdapter/StatsReadOnlySource.swift`
- Create: `Sources/StatsAdapter/StatsAdapterBoundary.swift`
- Create: `Tests/StatsAdapterTests/StatsAdapterBoundaryTests.swift`
- Create: `docs/architecture/stats-boundary.md`

- [ ] **Step 1: 写入边界测试**

  测试验证 `StatsReadOnlySource` 只包含 MVP 允许参考或迁移的只读来源：

  ```swift
  func testReadOnlySourcesStayWithinMVPBoundary() {
      XCTAssertEqual(Set(StatsReadOnlySource.allCases), [
          .hidSensors,
          .smcReadOnly,
          .batteryIORegistry,
          .nvmeSMART,
      ])
  }
  ```

- [ ] **Step 2: 实现可编译边界类型**

  创建 `StatsReadOnlySource` 和 `StatsAdapterBoundary`。`StatsAdapterBoundary` 只返回允许来源和禁止能力说明，不 import 或编译 `Vendor/Stats` 源码。

- [ ] **Step 3: 编写边界文档**

  `docs/architecture/stats-boundary.md` 必须写明：

  - `Vendor/Stats` 当前固定版本：`v3.0.1`。
  - `Vendor/Stats` 默认只读，不提交 MacWatch 业务代码。
  - 允许参考：HID Sensors、SMC 只读、电池 IORegistry、NVMe SMART、必要 IORegistry/IOReport 片段。
  - 禁止接入：Stats `Reader`、`Module` 生命周期、`DB.shared`、LevelDB、Remote、MQTT、OAuth、Updater、通知、Widget、LaunchAtLogin helper、SMC privileged helper、SMC 写操作。
  - `StatsAdapter` 不写 DB、不发通知、不联网、不持有 UI 状态。

- [ ] **Step 4: 运行 StatsAdapter 测试**

  Run: `swift test --filter StatsAdapterTests`

  Expected: `StatsAdapterTests` 全部通过。

- [ ] **Step 5: 提交**

  ```bash
  git add Sources/StatsAdapter Tests/StatsAdapterTests docs/architecture/stats-boundary.md
  git commit -m "docs: define Stats adapter boundary"
  ```

### Task 5: 建立构建、测试和边界扫描脚本

**Files:**

- Create: `scripts/build.sh`
- Create: `scripts/test.sh`
- Create: `scripts/run.sh`
- Create: `scripts/verify_stats_boundary.sh`
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

- [ ] **Step 1: 创建构建脚本**

  `scripts/build.sh` 执行：

  ```bash
  swift build
  ```

  脚本应设置 `set -euo pipefail`，从仓库根目录运行。

- [ ] **Step 2: 创建测试脚本**

  `scripts/test.sh` 执行：

  ```bash
  swift test
  ./scripts/verify_stats_boundary.sh
  ```

- [ ] **Step 3: 创建运行脚本**

  `scripts/run.sh` 执行：

  ```bash
  swift run MacWatchApp
  ```

- [ ] **Step 4: 创建 Stats 边界扫描脚本**

  `scripts/verify_stats_boundary.sh` 扫描 `Package.swift`、`Sources`、`Tests`、`docs`，排除 `Vendor/Stats`，命中以下禁止项时失败：

  ```text
  DB.shared
  SystemStats
  MQTT
  OAuth
  LaunchAtLogin
  SMC.Helper
  UserNotifications
  Reader(
  Reader<
  ```

  `Reader` 扫描需要避免误伤普通英文文档时，可限定在 Swift 文件或与 `Stats` 同行出现；执行阶段应在脚本注释中说明该规则。

- [ ] **Step 5: 创建 Codex Run 按钮入口**

  `script/build_and_run.sh` 调用 `scripts/build.sh` 后运行 `scripts/run.sh`。`.codex/environments/environment.toml` 指向该入口，使本地运行路径固定。

- [ ] **Step 6: 运行脚本验证**

  Run:

  ```bash
  ./scripts/build.sh
  ./scripts/test.sh
  ./scripts/verify_stats_boundary.sh
  ```

  Expected: 三个命令都返回退出码 `0`。

- [ ] **Step 7: 提交**

  ```bash
  git add scripts script .codex
  git commit -m "chore: add build test and boundary scripts"
  ```

### Task 6: 连接主窗口、设置页和菜单栏命令

**Files:**

- Modify: `Sources/MacWatchApp/AppDelegate.swift`
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarController.swift`
- Modify: `Sources/MacWatchApp/Views/ContentView.swift`
- Modify: `Sources/MacWatchApp/Views/SettingsView.swift`

- [ ] **Step 1: 主窗口展示阶段状态**

  `ContentView` 只展示工程骨架状态和下一阶段入口含义，例如：

  - App name: `MacWatch`
  - Status: `Engineering skeleton ready`
  - Temperature: 不显示 `0°C`，可显示 `No samples yet`

  不显示伪造温度。

- [ ] **Step 2: 设置页绑定最小设置**

  `SettingsView` 展示 `launchMainWindowOnStart` 这一项，使用 `AppSettings` 或 SwiftUI 本地状态承载。温度单位和刷新间隔不在阶段 1 实装，避免制造未接入业务的 UI 承诺。

- [ ] **Step 3: 菜单栏命令可用**

  `Open MacWatch` 激活 App 并打开主窗口；`Settings` 打开设置；`Quit MacWatch` 调用 `NSApp.terminate(nil)`。如果 `openWindow` 环境值不适合从 AppKit controller 直接调用，执行阶段可通过通知或 App 级 coordinator 桥接。

- [ ] **Step 4: 手动冒烟验证**

  Run: `./scripts/run.sh`

  Expected:

  - 菜单栏状态项出现。
  - 点击 `Open MacWatch` 后主窗口可见。
  - 点击 `Settings` 后设置窗口可见。
  - 点击 `Quit MacWatch` 后进程退出。

- [ ] **Step 5: 提交**

  ```bash
  git add Sources/MacWatchApp
  git commit -m "feat: wire menu bar window and settings commands"
  ```

### Task 7: 完成阶段 1 总体验证

**Files:**

- Modify: `docs/architecture/stats-boundary.md`
- No source changes unless前序任务验证发现缺口。

- [ ] **Step 1: 检查工作区没有误改 Vendor**

  Run: `git status --short Vendor/Stats`

  Expected: 无输出。

- [ ] **Step 2: 检查 submodule 版本**

  Run: `git submodule status -- Vendor/Stats`

  Expected: 输出包含 `Vendor/Stats (v3.0.1)`。

- [ ] **Step 3: 运行完整构建测试**

  Run:

  ```bash
  ./scripts/build.sh
  ./scripts/test.sh
  ```

  Expected:

  - `swift build` 成功。
  - `swift test` 成功。
  - `verify_stats_boundary.sh` 成功。

- [ ] **Step 4: 人工验收 macOS App 基础行为**

  Run: `./scripts/run.sh`

  验收：

  - App 可启动。
  - 菜单栏入口存在且由 `NSStatusItem` 管理。
  - 主窗口由 `WindowGroup` 提供。
  - 设置由 `Settings` scene 提供。
  - 退出菜单可结束 App。
  - 主窗口不展示 `0°C` 或伪造温度。

- [ ] **Step 5: 提交收口**

  ```bash
  git add docs/architecture/stats-boundary.md
  git commit -m "test: verify stage 1 engineering skeleton"
  ```

## 测试矩阵

| 验证项 | 命令 | 期望 |
| --- | --- | --- |
| Swift 编译 | `swift build` | 成功 |
| 全量单测 | `swift test` | 成功 |
| Core 单测 | `swift test --filter MacWatchCoreTests` | 成功 |
| StatsAdapter 单测 | `swift test --filter StatsAdapterTests` | 成功 |
| Stats 边界扫描 | `./scripts/verify_stats_boundary.sh` | 成功，未命中禁止项 |
| App 手动运行 | `swift run MacWatchApp` | 菜单栏、主窗口、设置、退出可用 |
| Vendor 未修改 | `git status --short Vendor/Stats` | 无输出 |
| Stats 版本固定 | `git submodule status -- Vendor/Stats` | 包含 `(v3.0.1)` |

## 阶段 1 验收标准

- 仓库根目录存在 `Package.swift`，并能构建 `MacWatchApp`、`MacWatchCore`、`StatsAdapter`。
- `Sources/MacWatchApp`、`Sources/MacWatchCore`、`Sources/StatsAdapter` 职责清晰，依赖方向符合本计划。
- App 可启动，菜单栏入口使用 AppKit `NSStatusItem`，主窗口使用 SwiftUI `WindowGroup`，设置使用 SwiftUI `Settings` scene。
- App 生命周期具备启动、退出、睡眠、唤醒事件入口，并通过 Core 单测覆盖事件记录。
- `StatsAdapter` 只提供只读边界空壳，不直接接入 `Vendor/Stats` 的 `Reader`、`DB.shared`、Remote、Updater、通知、helper。
- `Vendor/Stats` 没有被修改，submodule 仍固定在 `v3.0.1`。
- 存在可重复执行的构建、测试、运行和 Stats 边界扫描脚本。
- UI 不显示伪造温度，不把不可读温度显示为 `0°C`、空白或旧值。

## 下一阶段交接

阶段 1 完成后，阶段 2/3 应在该骨架上推进 CPU 温度端到端纵切：

```text
CPU 只读采集 -> TemperatureSample/Capability -> LiveTemperatureStore -> 会话历史 -> 菜单栏/详情趋势
```

后续扩展 GPU、内存、SSD/NAND、电池时复用同一 probe/capability/status 契约，不反向修改 UI 直接访问系统 API 或 `Vendor/Stats`。

## 自检结果

- Spec coverage：阶段 1 的工程结构、Stats 只读边界、macOS scene、生命周期、单测和构建脚本均有对应任务。
- Boundary coverage：计划明确禁止 Stats `Reader`、`DB.shared`、Remote、Updater、通知、helper，并增加静态扫描脚本。
- Code density：仅保留 target 摘要、接口签名、测试样例和扫描 schema；未写入整文件级实现。
- Type consistency：`AppLifecycleEvent`、`AppLifecycleCoordinator`、`AppSettings`、`StatsReadOnlySource` 名称在任务和测试中一致。
