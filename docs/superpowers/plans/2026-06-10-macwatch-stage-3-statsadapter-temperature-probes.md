# MacWatch 阶段 3：StatsAdapter 与温度采集能力验证 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 打通真实 CPU 温度读取到实时状态、当前会话历史、菜单栏和详情趋势的端到端链路，并为 GPU、内存、SSD/NAND、电池建立可验证的能力检测与读取尝试。

**Architecture:** 阶段 3 通过 `MacWatchCore` 定义 `TemperatureProbe` 契约和采样编排，通过 `StatsAdapter` 迁移或包装 Stats 中必要的只读 HID、SMC、Battery IORegistry、NVMe SMART 温度读取逻辑。执行顺序必须先完成 CPU 温度纵切，再扩展 GPU、内存、SSD/NAND、电池；所有不可读指标必须产出 `unsupported` 或 `readFailed` 样本和 capability，不能静默隐藏。

**Tech Stack:** Swift Package Manager, Swift, XCTest, AppKit `NSStatusItem`, SwiftUI, Charts, IOKit, IOHID, IORegistry, DiskArbitration, NVMe SMART, macOS 13 Ventura 及以上。

---

## 代码片段控制规则

本计划遵循本次任务对 `superpowers:writing-plans` 的最新规定：计划文档写清目标、架构、文件路径、接口契约、测试与验收；只在关键、易误解、强约束处放小段接口签名、关键数据结构、测试样例和边界处理伪代码。整文件级业务逻辑、普通样板代码、完整组件实现和可由测试与接口约束自然推导出的代码，进入执行阶段的代码仓库和 PR，不在本计划中展开。

## 需求来源

- `docs/origin/MacWatch_MVP版需求文档.md`：MVP 温度指标、状态、数据来源优先级、菜单栏、Popup、Dashboard、趋势、历史、隐私和验收标准。
- `docs/origin/MacWatch_技术架构文档.md`：分层架构、`MacWatchCore`/`StatsAdapter`/`MacWatchApp` 职责、采样调度和 UI 访问边界。
- `docs/origin/Stats_功能梳理_事实版.md`：Stats 模块事实边界。
- `docs/origin/Stats复用策略.md`：`Vendor/Stats` 只读、固定 `v3.0.1`、只通过 `StatsAdapter` 隔离。
- `docs/architecture/stats-boundary.md`：允许参考来源和禁止接入能力。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-1-engineering-skeleton.md`：工程骨架、SwiftPM target、Stats 边界扫描脚本。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-2-temperature-domain-session-history.md`：温度领域模型、当前会话历史和 SQLite schema 契约。

## Stats 源码核验结论

阶段 3 执行前必须把以下核验结论固化到 `docs/architecture/stats-temperature-source-audit.md`，作为代码迁移依据。

| Stats 文件 | 可复用只读点 | 明确排除点 |
| --- | --- | --- |
| `Vendor/Stats/Modules/Sensors/readers.swift` | SMC 温度 key 枚举、HID 传感器初始化、HID 温度过滤、CPU/GPU/SOC 平均和最高值计算思路 | `Reader<Sensors_List>` 生命周期、`Store.shared` 开关、IOReport power 采样、fan 相关计算、callback 模块体系 |
| `Vendor/Stats/Modules/Sensors/reader.m` | `IOHIDEventSystemClient` 读取 Apple Silicon HID 温度事件的最小 C/ObjC shim | 直接把 Stats bridge 或模块 target 接入 MacWatch |
| `Vendor/Stats/Modules/Sensors/values.swift` | Apple Silicon SMC key、HID key 到显示名和 domain 的映射；M4 CPU/GPU/Memory/NAND/Battery 关键 key | 电压、电流、功耗、风扇、非温度传感器 |
| `Vendor/Stats/Modules/CPU/readers.swift` | Apple Silicon 平台到 CPU SMC key list 的 fallback；`TC0D`/`TC0E`/`TC0F`/`TC0P`/`TC0H` legacy fallback | CPU 负载、进程列表、频率、IOReport 频率采样 |
| `Vendor/Stats/Modules/GPU/reader.swift` | `IOAccelerator` `PerformanceStatistics["Temperature(C)"]` 作为 GPU 温度候选 fallback | GPU 利用率、FPS、ANE 功耗、renderer/tiler、进程或显示统计 |
| `Vendor/Stats/Modules/Disk/readers.swift` | 内置 NVMe SMART 温度读取和 Kelvin 到 Celsius 转换；SMART capability 判断 | 磁盘容量、I/O 活动、读写总量、外接盘策略 |
| `Vendor/Stats/Modules/Battery/readers.swift` | `AppleSmartBattery` IORegistry `Temperature` 属性，单位为 centi-Celsius，需要除以 `100.0` | 电池电量曲线、健康度、充放电功率、通知、进程能耗 |
| `Vendor/Stats/SMC/smc.swift` | `AppleSMC` open/read/key info/decode 和 `getAllKeys()` 只读逻辑 | `write`、`setFanMode`、`setFanSpeed`、`unlockFanControl`、`resetFanControl`、任何 SMC 写操作或 privileged helper |
| `Vendor/Stats/Kit/plugins/SystemKit.swift` | Apple Silicon 平台枚举、model/chip 识别、必要 IORegistry/sysctl 读取片段 | `system_profiler` 大范围资源信息、序列号采集、图标资源、非温度硬件详情 |

关键 sensor/key 归类摘要：

| Domain | 优先来源 | 关键 raw key 或属性 |
| --- | --- | --- |
| `cpu` | HID Sensors，fallback SMC | HID `pACC MTR Temp Sensor%`、`eACC MTR Temp Sensor%`; M4 SMC `Te05`、`Te09`、`Te0H`、`Te0S`、`Tp01`、`Tp05`、`Tp09`、`Tp0D`、`Tp0V`、`Tp0Y`、`Tp0b`、`Tp0e`; legacy SMC `TC0D`、`TC0E`、`TC0F`、`TC0P`、`TC0H` |
| `gpu` | HID Sensors，fallback SMC 或 IOAccelerator | HID `GPU MTR Temp Sensor%`; M4 SMC `Tg0G`、`Tg0H`、`Tg1U`、`Tg1k`、`Tg0K`、`Tg0L`、`Tg0d`、`Tg0e`、`Tg0j`、`Tg0k`; IOAccelerator `PerformanceStatistics.Temperature(C)` |
| `memory` | SMC/HID key catalog | M4 SMC `Tm0p`、`Tm1p`、`Tm2p`; M1 SMC `Tm02`、`Tm06`、`Tm08`、`Tm09`; HID 中未确认语义的 memory-like key 必须保留 raw key |
| `ssd` | NVMe SMART，fallback HID/SMC NAND | SMART log `temperature`; SMC `TH0x`; HID `NAND CH% temp` |
| `battery` | Battery IORegistry，fallback HID/SMC | `AppleSmartBattery.Temperature`; HID `gas gauge battery`; SMC `TB1T`、`TB2T` |
| `system`/`sensor` | HID/SMC supplemental | `SOC MTR Temp Sensor%`、`PMGR SOC Die Temp Sensor%`、`ANE MTR Temp Sensor%`、`ISP MTR Temp Sensor%` 等无法归入五类硬件的温度 |

## 阶段 3 范围

阶段 3 包含：

- 定义 `TemperatureProbe` 协议和 probe 编排服务。
- 实现 CPU 温度 probe，优先读取 Apple Silicon HID CPU 温度，fallback 到只读 SMC CPU key。
- 将 CPU `valid` 或失败状态写入实时状态和当前会话历史。
- 让菜单栏默认显示最高有效温度；CPU 纵切完成前至少显示 CPU 温度或明确不可读状态。
- 主窗口提供当前温度列表和 CPU 当前会话趋势视图，趋势查询复用阶段 2 repository。
- 实现 GPU、内存、SSD/NAND、电池 probe 的 capability detection 和读取尝试。
- 对不可读指标写入 `unsupported` 或 `readFailed`，并保留 `rawKey`、IORegistry property、SMART 标识或 source-specific attributes。
- 增强 Stats 边界扫描，防止禁止能力进入默认链路。
- 提供 fake probe 单测、adapter 映射单测和可手动执行的真实硬件 probe 验证脚本。

阶段 3 不包含：

- 不实现资源监控、进程统计、CPU/GPU/ANE/RAM 使用率或功耗趋势。
- 不实现告警、通知、导出、云同步、远程监控、Widget、风扇控制。
- 不引入长期跨会话历史。
- 不接入 Stats `Reader`、`Module` 生命周期、`DB.shared`、LevelDB、Remote、SystemStats、MQTT、OAuth、Updater、LaunchAtLogin helper、privileged helper。
- 不写 `Vendor/Stats`。
- 不通过算法估算不可读温度。

## 目标文件结构

```text
Package.swift
Sources/
  MacWatchCore/
    Temperature/
      TemperatureMetricName.swift
      TemperatureProbe.swift
      TemperatureMonitorService.swift
      LiveTemperatureState.swift
  StatsAdapter/
    Diagnostics/
      TemperatureProbeDiagnostics.swift
    Hardware/
      ApplePlatform.swift
      ApplePlatformDetector.swift
      SMCReadOnlyClient.swift
      BatteryTemperatureIORegistryReader.swift
      NVMeSMARTTemperatureReader.swift
      IOAcceleratorTemperatureReader.swift
    Probes/
      StatsTemperatureProbeFactory.swift
      AppleSiliconSensorCatalog.swift
      CPUTemperatureProbe.swift
      GPUTemperatureProbe.swift
      MemoryTemperatureProbe.swift
      SSDTemperatureProbe.swift
      BatteryTemperatureProbe.swift
  StatsAdapterIOHID/
    include/
      StatsAdapterIOHID.h
    AppleSiliconHIDSensors.m
  MacWatchApp/
    Runtime/
      MacWatchRuntime.swift
    MenuBar/
      MenuBarController.swift
    Views/
      TemperatureDashboardView.swift
      TemperatureTrendView.swift
      ContentView.swift
scripts/
  probe_temperature_once.sh
  verify_stats_boundary.sh
docs/
  architecture/
    stats-temperature-source-audit.md
Tests/
  MacWatchCoreTests/
    TemperatureMonitorServiceTests.swift
  StatsAdapterTests/
    AppleSiliconSensorCatalogTests.swift
    CPUTemperatureProbeTests.swift
    DomainTemperatureProbeTests.swift
    StatsBoundaryScriptTests.swift
```

如果执行阶段发现 SwiftPM 不接受 Swift 与 Objective-C 在同一 target 中混编，必须保留 `StatsAdapterIOHID` 作为独立 clang target，并让 `StatsAdapter` 依赖该 target。不要把 `reader.m` 直接丢进 `StatsAdapter` Swift target。

## 接口契约

### `TemperatureProbe` 契约

`TemperatureProbe` 属于 `MacWatchCore`，让 `MacWatchApp` 和 `StatsAdapter` 都依赖同一个领域协议。Probe 不能持有 UI 状态，也不能直接写 repository。

```swift
public protocol TemperatureProbe: Sendable {
    var domain: TemperatureDomain { get }
    var source: TemperatureSource { get }
    var defaultMetricName: String { get }

    func detect(sessionID: UUID, at timestamp: Date) async -> TemperatureCapability
    func read(sessionID: UUID, at timestamp: Date) async -> [TemperatureSample]
}
```

强约束：

- `read` 至少返回一个样本。不可用时返回 `unsupported` 或 `readFailed` 样本，不返回空数组。
- `valid` 样本必须有 `valueCelsius`；非 `valid` 样本必须没有 `valueCelsius`。
- 每个样本必须保留 `rawKey` 或在 `attributes` 中保留 `rawKeys`、`ioRegistryProperty`、`smartField`、`sourcePriority`、`readerError` 中至少一种。
- 单个 probe 抛错或读取失败不得影响其他 probe；编排层把异常转换为 `readFailed`。

### 指标名契约

阶段 3 只新增常量，不修改阶段 2 已固定的 raw value。执行阶段应把下列名字放入 `TemperatureMetricName.swift`，避免 UI、历史和 adapter 各写字符串。

```swift
public enum TemperatureMetricName {
    public static let cpuHottest = "cpu.temperature.hottest"
    public static let cpuAverage = "cpu.temperature.average"
    public static let gpuHottest = "gpu.temperature.hottest"
    public static let memoryProximity = "memory.temperature.proximity"
    public static let ssdInternal = "ssd.temperature.internal"
    public static let battery = "battery.temperature"
    public static let systemHottest = "system.temperature.hottest"
}
```

### `LiveTemperatureState` 契约

实时状态在 `MacWatchCore` 中保持 Swift/Sendable 数据结构；`MacWatchApp` 可包装成 `ObservableObject`，但 UI 不直接访问 IOKit、SMC、SMART、IORegistry 或 `Vendor/Stats`。

```swift
public struct LiveTemperatureState: Equatable, Sendable {
    public let sessionID: UUID
    public let updatedAt: Date?
    public let samplesByMetricName: [String: TemperatureSample]
    public let capabilitiesByDomain: [TemperatureDomain: TemperatureCapability]
    public let hottestValidSample: TemperatureSample?
}
```

最高温度计算规则：

- 只看 `quality == .valid` 且 `valueCelsius != nil` 的样本。
- `unsupported`、`readFailed`、`stale` 不参与最高温度。
- 如果没有有效温度，菜单栏显示短状态，例如 `--°C` 或 `CPU unavailable`，不能显示 `0°C`。

### `TemperatureMonitorService` 契约

采样服务负责调用 probes、更新实时状态、写入当前会话历史。默认计划先提供 `sampleOnce`，再在 App runtime 中用定时器按刷新间隔调用；不要在 adapter 内部创建全局 timer。

```swift
public final class TemperatureMonitorService {
    public init(
        probes: [any TemperatureProbe],
        repository: any SessionHistoryRepository,
        clock: @escaping @Sendable () -> Date
    )

    public func detectCapabilities(sessionID: UUID) async -> LiveTemperatureState
    public func sampleOnce(sessionID: UUID) async -> LiveTemperatureState
}
```

写入规则：

- `detectCapabilities` 写入 `temperature_capability`，并生成每个 domain 的初始 state。
- `sampleOnce` 写入所有 probe 返回的样本；repository 写入失败时仍返回实时状态，并记录 `historyWriteFailed` timeline event。
- CPU 纵切阶段允许只启用 CPU probe；横向阶段必须让五类 domain 都有状态。

### StatsAdapter 原始读取契约

`StatsAdapter` 内部可以使用轻量 raw reading 结构承接 HID/SMC/IORegistry/SMART 结果，但只把 `TemperatureSample` 和 `TemperatureCapability` 暴露给 Core/App。

```swift
internal struct RawTemperatureReading: Equatable, Sendable {
    let domain: TemperatureDomain
    let displayName: String
    let valueCelsius: Double
    let source: TemperatureSource
    let rawKey: String
    let attributes: [String: String]
}
```

边界处理伪代码：

```swift
if valueCelsius.isNaN || valueCelsius < 0 || valueCelsius >= 110 {
    dropRawReadingButReturnReadFailedIfDomainHasNoValidReading()
}
```

过滤阈值来自 Stats Sensors 温度过滤思路；执行阶段可以把上限写成常量并在测试中锁定。不要把无效原始值包装成 `valid`。

## 实施任务

### Task 1: 固化 Stats 温度来源核验文档

**Files:**

- Create: `docs/architecture/stats-temperature-source-audit.md`
- Modify: `docs/architecture/stats-boundary.md`

- [ ] **Step 1: 写来源核验文档**

  将本计划“Stats 源码核验结论”整理为独立文档，逐文件列出可复用只读点、排除点、关键 raw key 和验证风险。文档必须明确 `Vendor/Stats` 保持只读，且 `StatsAdapter` 不接入 Stats `Reader`/`Module`。

- [ ] **Step 2: 更新边界文档**

  在 `docs/architecture/stats-boundary.md` 增加阶段 3 允许迁移的最小只读实现：HID 温度 shim、SMC read-only client、Battery IORegistry temperature reader、NVMe SMART temperature reader、IOAccelerator GPU temperature candidate。

- [ ] **Step 3: 验证文档不包含占位符**

  Run: `rg -n "TBD|TODO|implement later|fill in" docs/architecture/stats-temperature-source-audit.md docs/architecture/stats-boundary.md`

  Expected: 无输出。

- [ ] **Step 4: Commit**

  ```bash
  git add docs/architecture/stats-temperature-source-audit.md docs/architecture/stats-boundary.md
  git commit -m "docs: audit Stats temperature sources"
  ```

### Task 2: 定义 Core probe 与实时状态契约

**Files:**

- Create: `Sources/MacWatchCore/Temperature/TemperatureMetricName.swift`
- Create: `Sources/MacWatchCore/Temperature/TemperatureProbe.swift`
- Create: `Sources/MacWatchCore/Temperature/LiveTemperatureState.swift`
- Create: `Sources/MacWatchCore/Temperature/TemperatureMonitorService.swift`
- Create: `Tests/MacWatchCoreTests/TemperatureMonitorServiceTests.swift`

- [ ] **Step 1: 写 failing tests**

  测试覆盖三条强约束：CPU `valid` 写入历史并进入 hottest；`unsupported` 不参与 hottest；probe 失败被转换为 `readFailed` 且不阻断其他 probe。

  ```swift
  XCTAssertEqual(state.hottestValidSample?.metricName, TemperatureMetricName.cpuHottest)
  XCTAssertNil(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.valueCelsius)
  XCTAssertEqual(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.quality, .unsupported)
  ```

- [ ] **Step 2: 运行测试确认失败**

  Run: `swift test --filter TemperatureMonitorServiceTests`

  Expected: 因 `TemperatureProbe`、`TemperatureMonitorService` 尚不存在而失败。

- [ ] **Step 3: 实现接口与最小编排**

  按“接口契约”创建 protocol、metric constants、live state 和 monitor service。`TemperatureMonitorService` 不 import SwiftUI、AppKit、IOKit 或 `StatsAdapter`。

- [ ] **Step 4: 运行 Core 测试**

  Run: `swift test --filter MacWatchCoreTests`

  Expected: `MacWatchCoreTests` 全部通过。

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/MacWatchCore/Temperature Tests/MacWatchCoreTests/TemperatureMonitorServiceTests.swift
  git commit -m "feat: define temperature probe monitoring contracts"
  ```

### Task 3: 实现 StatsAdapter 只读硬件基础层

**Files:**

- Modify: `Package.swift`
- Create: `Sources/StatsAdapterIOHID/include/StatsAdapterIOHID.h`
- Create: `Sources/StatsAdapterIOHID/AppleSiliconHIDSensors.m`
- Create: `Sources/StatsAdapter/Hardware/ApplePlatform.swift`
- Create: `Sources/StatsAdapter/Hardware/ApplePlatformDetector.swift`
- Create: `Sources/StatsAdapter/Hardware/SMCReadOnlyClient.swift`
- Create: `Sources/StatsAdapter/Hardware/BatteryTemperatureIORegistryReader.swift`
- Create: `Sources/StatsAdapter/Hardware/NVMeSMARTTemperatureReader.swift`
- Create: `Sources/StatsAdapter/Hardware/IOAcceleratorTemperatureReader.swift`
- Modify: `scripts/verify_stats_boundary.sh`
- Modify: `Tests/StatsAdapterTests/StatsBoundaryScriptTests.swift`

- [ ] **Step 1: 写边界扫描 failing tests**

  扩展 fixture，确认 `Sources/StatsAdapter` 中出现以下禁止项时扫描失败：`write(`、`setFanSpeed`、`setFanMode`、`unlockFanControl`、`resetFanControl`、`FanMode`、`DB.shared`、`SystemStats`、`Remote`、`Updater`、`LevelDB`、`UserNotifications`、`Reader<`、`Module(`。

- [ ] **Step 2: 运行测试确认失败**

  Run: `swift test --filter StatsBoundaryScriptTests`

  Expected: 新增禁止项尚未被脚本捕获，测试失败。

- [ ] **Step 3: 增加 SwiftPM clang target**

  在 `Package.swift` 增加内部 target `StatsAdapterIOHID`，让 `StatsAdapter` 依赖它。`MacWatchApp` 仍只依赖 `StatsAdapter` 和 `MacWatchCore`。

- [ ] **Step 4: 实现只读硬件基础层**

  迁移时只取最小能力：

  - `AppleSiliconHIDSensors.m`：封装 `IOHIDEventSystemClient` 温度事件读取，返回 key/value dictionary。
  - `ApplePlatformDetector`：用 `sysctl`/CPU brand string 判断 `m1` 至 `m5` 平台，不采集序列号。
  - `SMCReadOnlyClient`：只实现 open/read/key info/decode/getAllKeys/getValue，不包含任何 write 或 fan API。
  - `BatteryTemperatureIORegistryReader`：只读取 `AppleSmartBattery` 的 `Temperature` property。
  - `NVMeSMARTTemperatureReader`：只读取内置 NVMe SMART 温度，不返回容量、读写量、健康度。
  - `IOAcceleratorTemperatureReader`：只尝试读取 `PerformanceStatistics["Temperature(C)"]`。

- [ ] **Step 5: 运行边界与 adapter 测试**

  Run: `swift test --filter StatsAdapterTests && ./scripts/verify_stats_boundary.sh`

  Expected: 测试和边界扫描均通过。

- [ ] **Step 6: Commit**

  ```bash
  git add Package.swift Sources/StatsAdapter Sources/StatsAdapterIOHID scripts/verify_stats_boundary.sh Tests/StatsAdapterTests
  git commit -m "feat: add read-only temperature hardware adapters"
  ```

### Task 4: 实现 Apple Silicon sensor catalog 与 CPU probe

**Files:**

- Create: `Sources/StatsAdapter/Probes/AppleSiliconSensorCatalog.swift`
- Create: `Sources/StatsAdapter/Probes/CPUTemperatureProbe.swift`
- Create: `Tests/StatsAdapterTests/AppleSiliconSensorCatalogTests.swift`
- Create: `Tests/StatsAdapterTests/CPUTemperatureProbeTests.swift`

- [ ] **Step 1: 写 catalog mapping tests**

  测试锁定 M4 CPU key、HID CPU prefix、显示名和 domain。不要测试 Stats 全量 sensor list，只测试 MVP 需要的温度 key。

  ```swift
  XCTAssertEqual(catalog.domain(forRawKey: "pACC MTR Temp Sensor0"), .cpu)
  XCTAssertEqual(catalog.domain(forRawKey: "eACC MTR Temp Sensor1"), .cpu)
  XCTAssertTrue(catalog.smcCPUKeys(for: .m4).contains("Te05"))
  XCTAssertTrue(catalog.smcCPUKeys(for: .m4).contains("Tp0e"))
  ```

- [ ] **Step 2: 写 CPU probe tests**

  使用 fake HID reader 和 fake SMC client 验证优先级：

  - HID 有 `pACC`/`eACC` 有效值时，CPU hottest 来自 HID。
  - HID 无有效值但 SMC 有 M4 CPU key 时，fallback 到 SMC。
  - 所有来源不可读时，返回 `readFailed`，`rawKey` 为空但 `attributes["attemptedRawKeys"]` 非空。
  - `-1`、`NaN`、`110` 及以上温度不会变成 `valid`。

- [ ] **Step 3: 运行测试确认失败**

  Run: `swift test --filter CPUTemperatureProbeTests`

  Expected: 因 catalog 和 CPU probe 尚不存在而失败。

- [ ] **Step 4: 实现 CPU probe**

  输出至少包含 `cpu.temperature.hottest`；如果有两个及以上 CPU raw readings，再输出 `cpu.temperature.average`。每个样本保留 winning `rawKey`，并在 attributes 中记录全部有效 raw keys。

- [ ] **Step 5: 运行 adapter 测试**

  Run: `swift test --filter StatsAdapterTests`

  Expected: 全部通过。

- [ ] **Step 6: Commit**

  ```bash
  git add Sources/StatsAdapter/Probes Tests/StatsAdapterTests/AppleSiliconSensorCatalogTests.swift Tests/StatsAdapterTests/CPUTemperatureProbeTests.swift
  git commit -m "feat: add CPU temperature probe"
  ```

### Task 5: 打通 CPU 端到端 runtime、菜单栏和趋势

**Files:**

- Create: `Sources/StatsAdapter/Probes/StatsTemperatureProbeFactory.swift`
- Create: `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift`
- Modify: `Sources/MacWatchApp/MacWatchApp.swift`
- Modify: `Sources/MacWatchApp/AppDelegate.swift`
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarController.swift`
- Create: `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`
- Create: `Sources/MacWatchApp/Views/TemperatureTrendView.swift`
- Modify: `Sources/MacWatchApp/Views/ContentView.swift`
- Add or modify: `Tests/MacWatchAppTests/*Temperature*Tests.swift`

- [ ] **Step 1: 写 App 层 tests**

  测试菜单栏标题格式和 UI view model，不访问真实硬件。关键断言：

  ```swift
  XCTAssertEqual(MenuBarTemperatureFormatter.title(forCelsius: 72.4), "72°C")
  XCTAssertEqual(MenuBarTemperatureFormatter.title(forUnavailableMetric: .cpu), "--°C")
  ```

- [ ] **Step 2: 运行测试确认失败**

  Run: `swift test --filter MacWatchAppTests`

  Expected: 新 formatter/runtime/view model 尚不存在，测试失败。

- [ ] **Step 3: 接入 CPU-only runtime**

  `StatsTemperatureProbeFactory` 先只启用 `CPUTemperatureProbe`。`MacWatchRuntime` 在 app 启动后获取当前 session，执行 capability detection，随后按设置或默认 5 秒调用 `sampleOnce`。定时器存在于 App 层，不在 `StatsAdapter`。

- [ ] **Step 4: 更新菜单栏**

  `MenuBarController` 增加更新标题的方法。默认显示 hottest valid sample；CPU 纵切期间没有有效值时显示 `--°C`，菜单内显示 CPU 状态和最近更新时间。

- [ ] **Step 5: 更新主窗口**

  `ContentView` 改为展示 `TemperatureDashboardView`。CPU 有效时展示当前 CPU 温度、来源、raw key、更新时间；无效时展示 `unsupported` 或 `readFailed` 的原因。`TemperatureTrendView` 用 repository query 读取当前 session 的 CPU 样本，图表遇到阶段 2 gap event 时断开。

- [ ] **Step 6: 运行构建与测试**

  Run: `swift test && swift build && ./scripts/verify_stats_boundary.sh`

  Expected: 全部通过。

- [ ] **Step 7: 手动运行 CPU 纵切**

  Run: `swift run MacWatchApp`

  Expected: App 启动后菜单栏显示真实 CPU 温度或明确不可读状态；主窗口显示 CPU 当前值、source、raw key 和当前会话趋势；不可读时不显示 `0°C`。

- [ ] **Step 8: Commit**

  ```bash
  git add Sources/StatsAdapter/Probes/StatsTemperatureProbeFactory.swift Sources/MacWatchApp Tests/MacWatchAppTests
  git commit -m "feat: connect CPU temperature end to end"
  ```

### Task 6: 扩展 GPU、内存、SSD/NAND、电池 probes

**Files:**

- Modify: `Sources/StatsAdapter/Probes/AppleSiliconSensorCatalog.swift`
- Create: `Sources/StatsAdapter/Probes/GPUTemperatureProbe.swift`
- Create: `Sources/StatsAdapter/Probes/MemoryTemperatureProbe.swift`
- Create: `Sources/StatsAdapter/Probes/SSDTemperatureProbe.swift`
- Create: `Sources/StatsAdapter/Probes/BatteryTemperatureProbe.swift`
- Modify: `Sources/StatsAdapter/Probes/StatsTemperatureProbeFactory.swift`
- Create or modify: `Tests/StatsAdapterTests/DomainTemperatureProbeTests.swift`

- [ ] **Step 1: 写 domain probe tests**

  测试五类 domain 都会输出状态：

  - GPU：HID `GPU MTR Temp Sensor%` 优先；fallback 到 SMC GPU key 或 IOAccelerator temperature；都不可读时 `unsupported` 或 `readFailed`。
  - Memory：M4 `Tm0p`/`Tm1p`/`Tm2p` 可读时输出 `memory.temperature.proximity`。
  - SSD：NVMe SMART temperature 可读时输出 `ssd.temperature.internal`；外接盘不进入结果。
  - Battery：`AppleSmartBattery.Temperature` 可读时除以 `100.0` 输出 Celsius。
  - 每个不可读 domain 都不会从状态列表消失。

- [ ] **Step 2: 运行测试确认失败**

  Run: `swift test --filter DomainTemperatureProbeTests`

  Expected: domain probes 尚不存在，测试失败。

- [ ] **Step 3: 实现 probes**

  每个 probe 独立 detect/read。读取顺序遵循 MVP 数据来源优先级：HID/SMC 温度用于 Apple Silicon 通用温度，Battery IORegistry 优先用于电池，NVMe SMART 优先用于内置 SSD/NAND。IOReport 只保留为 candidate，不把未经验证的 power channel 当温度。

- [ ] **Step 4: 更新 factory 启用五类 probes**

  `StatsTemperatureProbeFactory` 默认返回 CPU、GPU、Memory、SSD、Battery。任一 probe 初始化失败时，factory 仍返回其他 probes，并用对应 domain 的 unsupported capability 表达失败原因。

- [ ] **Step 5: 运行 adapter 测试**

  Run: `swift test --filter StatsAdapterTests && ./scripts/verify_stats_boundary.sh`

  Expected: 全部通过。

- [ ] **Step 6: Commit**

  ```bash
  git add Sources/StatsAdapter/Probes Tests/StatsAdapterTests/DomainTemperatureProbeTests.swift
  git commit -m "feat: add temperature probes for supported domains"
  ```

### Task 7: UI 展示所有 domain 状态并保留不可读指标

**Files:**

- Modify: `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureTrendView.swift`
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarController.swift`
- Modify: `Tests/MacWatchAppTests/*Temperature*Tests.swift`

- [ ] **Step 1: 写 UI 状态测试**

  使用 fake live state 验证 GPU、Memory、SSD、Battery 即使不可读也会显示状态文案；最高温度只取 valid 样本。

- [ ] **Step 2: 运行测试确认失败**

  Run: `swift test --filter MacWatchAppTests`

  Expected: 当前 UI 尚未显示五类 domain 状态，测试失败。

- [ ] **Step 3: 更新 dashboard**

  主窗口显示 CPU、GPU、内存、SSD/NAND、电池五类当前状态。有效样本显示温度、source、raw key；不可读显示 `unsupported` 或 `readFailed`、reason code 和 source。

- [ ] **Step 4: 更新趋势入口**

  趋势视图允许选择 CPU、GPU、内存、SSD/NAND、电池。不可读 domain 显示状态说明，不画伪造曲线。CPU 趋势仍是阶段 3 硬验收重点。

- [ ] **Step 5: 运行测试与手动 UI 验证**

  Run: `swift test && swift build`

  Expected: 自动测试通过；手动运行时五类 domain 不会因为不可读而消失。

- [ ] **Step 6: Commit**

  ```bash
  git add Sources/MacWatchApp Tests/MacWatchAppTests
  git commit -m "feat: show temperature capabilities in app UI"
  ```

### Task 8: 增加真实硬件 probe 诊断脚本与验收记录

**Files:**

- Create: `Sources/StatsAdapter/Diagnostics/TemperatureProbeDiagnostics.swift`
- Create: `scripts/probe_temperature_once.sh`
- Modify: `scripts/test.sh`
- Create or modify: `docs/architecture/stats-temperature-source-audit.md`

- [ ] **Step 1: 增加诊断入口**

  `TemperatureProbeDiagnostics` 提供一次性读取函数，输出 JSON lines 或清晰文本。输出必须包含 domain、metricName、quality、valueCelsius、source、rawKey、errorCode、attributes。

- [ ] **Step 2: 增加脚本**

  `scripts/probe_temperature_once.sh` 调用 SwiftPM 构建产物或 `swift run MacWatchApp --probe-temperature-once`。脚本只读硬件，不启动长期采样，不写 Stats DB，不联网。

- [ ] **Step 3: 运行真实硬件验证**

  Run: `./scripts/probe_temperature_once.sh`

  Expected on MacBook Air M4: 至少一条 `cpu.temperature.hottest` 为 `valid`，`valueCelsius` 在合理范围内，且包含 HID 或 SMC raw key。GPU、内存、SSD/NAND、电池输出 `valid`、`unsupported` 或 `readFailed`，不能缺席。

- [ ] **Step 4: 记录验收结果**

  将真实硬件验证命令、机器类型、macOS 版本、CPU raw key、各 domain 状态摘要写入 `docs/architecture/stats-temperature-source-audit.md` 的“阶段 3 验收记录”小节。不要记录序列号、用户文件名、进程列表、窗口标题或网络内容。

- [ ] **Step 5: 运行全量验证**

  Run: `./scripts/test.sh && swift build && git status --short Vendor/Stats`

  Expected: 测试和边界扫描通过；`Vendor/Stats` 无修改。

- [ ] **Step 6: Commit**

  ```bash
  git add Sources/StatsAdapter/Diagnostics scripts/probe_temperature_once.sh scripts/test.sh docs/architecture/stats-temperature-source-audit.md
  git commit -m "test: add temperature probe diagnostics"
  ```

## 测试矩阵

| 验证项 | 命令 | 期望 |
| --- | --- | --- |
| Core probe 编排 | `swift test --filter TemperatureMonitorServiceTests` | CPU valid 写历史，unsupported/readFailed 不参与 hottest，probe 失败不阻断其他 probe |
| Adapter catalog/probe | `swift test --filter StatsAdapterTests` | key mapping、CPU priority、五类 domain 状态、边界扫描 fixture 通过 |
| App 状态展示 | `swift test --filter MacWatchAppTests` | 菜单栏 formatter、不可读 domain 展示、最高温度规则通过 |
| 全量单测 | `swift test` | 全部通过 |
| 构建 | `swift build` | `MacWatchApp`、`MacWatchCore`、`StatsAdapter`、`StatsAdapterIOHID` 构建成功 |
| Stats 边界 | `./scripts/verify_stats_boundary.sh` | 未命中禁止项 |
| 真实硬件一次性 probe | `./scripts/probe_temperature_once.sh` | MacBook Air M4 至少 CPU 为 `valid`；其他 domain 不缺席 |
| App 手动运行 | `swift run MacWatchApp` | 菜单栏和主窗口显示真实温度或明确不可读状态，不显示 `0°C` 伪值 |
| Vendor 未修改 | `git status --short Vendor/Stats` | 无输出 |

## 阶段 3 验收标准

- `MacWatchCore` 存在 `TemperatureProbe`、`TemperatureMonitorService` 和 `LiveTemperatureState`，且不依赖 AppKit、SwiftUI、IOKit、SMC、SMART 或 `StatsAdapter`。
- `StatsAdapter` 实现只读温度 probe，不写数据库、不发通知、不联网、不持有 UI 状态。
- MacBook Air M4 验收机上 `cpu.temperature.hottest` 至少能读到一条 `valid` 样本，并进入实时状态、当前会话历史、菜单栏和主窗口 CPU 趋势。
- GPU、内存、SSD/NAND、电池 domain 均有 capability 和当前样本状态；不可读时显示 `unsupported` 或 `readFailed`，不能缺席，不能显示 `0°C`。
- 每条样本保留 source 和 raw identifier：HID sensor key、SMC key、IORegistry property 或 SMART field。
- 最高温度只从 `valid` 样本计算；不可读和 stale 样本不参与。
- 睡眠、读取失败和历史写入失败不补造数据；趋势查询继续使用阶段 2 gap event。
- `scripts/verify_stats_boundary.sh` 能阻止 Stats Remote、SystemStats、LevelDB、Updater、通知、Stats `Reader`/`Module`、SMC 写操作和风扇控制 API 进入默认链路。
- `Vendor/Stats` 未被修改。

## 风险与处理

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| SwiftPM 混编 Objective-C 与 Swift 受限 | HID shim 无法直接放进 `StatsAdapter` | 使用独立 `StatsAdapterIOHID` clang target，`StatsAdapter` 只调用其公开 C header |
| M4 Air 上 SMC CPU key 不可读 | CPU 硬验收失败 | CPU probe 优先 HID `pACC`/`eACC`；SMC 仅 fallback；诊断脚本输出 attempted raw keys |
| Battery 或 NVMe SMART 受系统限制 | 横向 domain 无法读到温度 | 输出 `unsupported` 或 `readFailed`，保留 IORegistry property/SMART field 和 reason code |
| IOAccelerator GPU 温度缺失 | GPU 可能不可读 | 不把 GPU 缺失视为 CPU 纵切失败；UI 和 capability 明确展示不可读 |
| 误接入 Stats 非 MVP 能力 | 隐私和边界违规 | 扩展边界扫描并在每次 `scripts/test.sh` 中执行 |
| 高频 SMART 或 sensor 枚举影响能耗 | App CPU/能耗偏高 | 实时默认 CPU/GPU 5 秒；内存、SSD、电池 30 秒；不要每次采样重新枚举昂贵资源，必要时缓存 capability |

## 执行顺序约束

1. 先完成 Task 1-5，确保 CPU 温度端到端纵切可运行。
2. CPU 纵切通过后再做 Task 6-7，横向补齐 GPU、内存、SSD/NAND、电池。
3. 最后做 Task 8 的真实硬件诊断和验收记录。
4. 任一阶段发现 CPU 在 MacBook Air M4 上无法读取时，暂停横向扩展，先修 CPU probe 优先级和 raw key 映射。

## 自查清单

- 规格覆盖：本计划覆盖 Stats 源码核验、`TemperatureProbe`、CPU 端到端、横向 domain probe、不可读状态、raw identifier 保留、禁止接入清单、测试与硬件验收。
- 代码片段粒度：仅包含接口签名、关键常量、测试断言和边界伪代码；未放入整文件业务逻辑或完整组件实现。
- 边界一致性：UI 只访问 runtime/live state/repository，不直接访问 IOKit、SMC、IORegistry、SMART 或 `Vendor/Stats`。
- MVP 范围：未引入资源监控、进程统计、告警、导出、云同步、远程监控、Widget、风扇控制或长期跨会话历史。
- 验证路径：自动测试、边界扫描、SwiftPM 构建、真实硬件一次性 probe 和手动 App 运行均有明确命令与期望。
