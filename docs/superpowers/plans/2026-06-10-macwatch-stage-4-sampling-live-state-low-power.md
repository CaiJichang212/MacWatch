# MacWatch 阶段 4：采样调度、实时状态与低能耗策略 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 MacWatch 的温度采集稳定、低成本、可恢复，先完成 CPU 温度端到端纵切，再扩展 GPU、内存、SSD/NAND、电池和系统传感器的独立调度与状态维护。

**Architecture:** 阶段 4 在 `MacWatchCore` 中引入能力检测服务、采样调度器、样本总线和实时状态 store，将阶段 3 的 App 侧快慢 timer 替换为按 probe/用途管理的调度策略。`StatsAdapter` 继续只提供 probe 与只读采集，UI 只订阅 `LiveTemperatureStore` 和查询 session history，不直接访问系统 API、SQLite 或 `Vendor/Stats`。

**Tech Stack:** Swift Package Manager, Swift concurrency, XCTest, AppKit lifecycle notifications, SwiftUI `ObservableObject`, MacWatchCore, StatsAdapter, IOKit/IOHID/SMC/Battery IORegistry/NVMe SMART 只读路径。

---

## 代码片段控制规则

本计划遵循本次任务对 `superpowers:writing-plans` 的最新规定：计划文档写清目标、架构、文件路径、接口契约、测试与验收；只在关键、易误解、强约束处放小段接口签名、测试样例、策略表、边界处理伪代码或 schema 摘要。整文件级业务逻辑、普通样板代码、完整组件实现和可由测试与接口约束自然推导出的代码，应进入执行阶段的代码仓库和 PR，不在本计划中展开。

## 需求来源

- `docs/origin/MacWatch_MVP版需求文档.md`：第 5、6、7、8、9、10、12 节定义温度指标、能力检测、实时展示、历史写入、数据缺口、性能能耗和验收标准。
- `docs/origin/MacWatch_技术架构文档.md`：第 5、6、8、9、15、16 节定义能力模型、实时状态、会话历史、timeline event、调度职责、高成本采集约束和项目目录建议。
- `docs/origin/Stats_功能梳理_事实版.md`：Stats `Reader` 会耦合 Store、DB、Remote/SystemStats，因此阶段 4 不复用 Stats 调度生命周期。
- `docs/origin/Stats复用策略.md`：`Vendor/Stats` 只读，MacWatch 只通过 `StatsAdapter` 包装或迁移必要只读采集逻辑。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-1-engineering-skeleton.md`：SwiftPM target 与 Stats 边界扫描基础。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-2-temperature-domain-session-history.md`：温度领域模型、session history、timeline event、query 契约。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-3-statsadapter-temperature-probes.md`：`TemperatureProbe`、CPU/GPU/内存/SSD/电池 probe 与真实硬件验证路径。

## 当前代码基线

阶段 4 以当前仓库中已经存在的阶段 1-3 结果为基线：

- `Sources/MacWatchCore/Temperature/TemperatureProbe.swift` 已定义 probe 契约。
- `Sources/MacWatchCore/Temperature/TemperatureMonitorService.swift` 已提供 `detectCapabilities(sessionID:)` 和 `sampleOnce(sessionID:)`，但采样、历史写入和实时状态仍耦合在服务内。
- `Sources/MacWatchCore/Temperature/LiveTemperatureState.swift` 只有值对象，没有长期维护、stale 判定或事件分发。
- `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift` 目前使用 App 侧 fast/slow `Timer`，需要迁移到 Core 调度器。
- `Sources/StatsAdapter/Probes/StatsTemperatureProbeFactory.swift` 已能创建 CPU/GPU 快 probe 与内存/SSD/电池慢 probe。
- `Sources/MacWatchCore/History/TimelineEvent.swift` 已包含 `system.sleep.started`、`system.sleep.ended`、`probe.stale`、`history.write_failed` 等阶段 4 需要的事件类型。

## 阶段 4 范围

包含：

- 实现 `TemperatureCapabilityService`，启动时对所有默认 probe 执行完整能力检测，并把 capability 写入当前 session history。
- 实现 `TemperatureScheduler`，为每个 probe 管理独立实时采样和历史写入间隔。
- 实现默认采样策略：CPU/GPU 实时 5 秒、历史 10 秒；内存/SSD/电池实时 30 秒、历史 60 秒；系统传感器实时 10 秒、历史 30 秒。
- 实现 `SampleBus`，把采样结果分发给 `LiveTemperatureStore` 和历史写入订阅者。
- 实现 `LiveTemperatureStore`，维护当前最高温、各指标状态、更新时间、最后有效样本和 stale 判断。
- 处理睡眠暂停、唤醒恢复、能力重检和数据缺口 timeline event。
- 过滤异常温度：小于 `0°C` 或大于 `110°C` 的读数不能进入 `valid` 状态。
- 先完成 CPU 温度端到端纵切：CPU probe -> scheduler -> sample bus -> live store -> session history -> 菜单栏/详情趋势。
- CPU 纵切验证通过后，再横向补齐 GPU、内存、SSD/NAND、电池和系统传感器。

不包含：

- 不新增资源监控、进程统计、功耗、告警、导出、云同步、远程监控、Widget、风扇控制或长期跨会话历史。
- 不修改 `Vendor/Stats`。
- 不复用 Stats `Reader`、`Module`、`DB.shared`、LevelDB、Remote、SystemStats、Updater、LaunchAtLogin helper 或 privileged helper。
- 不把不可读温度估算为 `valid`。
- 不让 UI 直接调用 IOKit、SMC、IOReport、DiskArbitration、SQLite 或 `Vendor/Stats`。

## 目标文件结构

```text
Sources/
  MacWatchCore/
    Temperature/
      TemperatureCapabilityService.swift      # 新增：启动和唤醒能力检测编排
      TemperatureScheduler.swift              # 新增：按 probe/用途独立调度
      TemperatureSamplingPolicy.swift         # 新增：默认间隔和最低安全间隔
      SampleBus.swift                         # 新增：样本事件分发
      LiveTemperatureStore.swift              # 新增：当前状态、最高温、stale 判定
      TemperatureReadingValidator.swift       # 新增：异常温度和样本状态边界
      TemperatureMonitorService.swift         # 修改：收敛为 probe 读取 helper 或由新组件替代
      LiveTemperatureState.swift              # 修改：补充 stale/lastValid 需要的只读字段
    Lifecycle/
      AppLifecycleCoordinator.swift           # 修改：桥接睡眠/唤醒/退出事件到调度器
    Settings/
      AppSettings.swift                       # 修改：补充温度刷新设置，仍保留低成本下限
  MacWatchApp/
    Runtime/
      MacWatchRuntime.swift                   # 修改：用 Core 调度器替代 fast/slow Timer
    MenuBar/
      MenuBarController.swift                 # 修改：显示 stale/unsupported/readFailed，不显示旧值为正常值
    Views/
      TemperatureDashboardView.swift          # 修改：从 LiveTemperatureStore 状态展示各指标
      TemperatureTrendView.swift              # 修改：确认趋势查询按缺口断线
Tests/
  MacWatchCoreTests/
    TemperatureCapabilityServiceTests.swift   # 新增
    TemperatureSchedulerTests.swift           # 新增
    SampleBusTests.swift                      # 新增
    LiveTemperatureStoreTests.swift           # 新增
    TemperatureReadingValidatorTests.swift    # 新增
  MacWatchAppTests/
    MacWatchRuntimeSchedulerTests.swift       # 新增或替换现有 Timer 行为测试
```

## 接口契约

### 采样策略

`TemperatureSamplingPolicy` 属于 `MacWatchCore`，必须把实时刷新和历史写入拆开，不能再用单个 fast/slow timer 隐式决定历史节奏。

| Domain | 实时刷新 | 历史写入 | 最低安全间隔 | 说明 |
| --- | --- | --- | --- | --- |
| `cpu` | 5s | 10s | 5s | CPU 纵切和 MVP 硬验收核心 |
| `gpu` | 5s | 10s | 5s | 支持时展示 |
| `memory` | 30s | 60s | 30s | 避免高频 sensor 枚举 |
| `ssd` | 30s | 60s | 30s | SMART 不低于 30s |
| `battery` | 30s | 60s | 30s | 可被电源事件触发额外读取，但不高频轮询 |
| `system`/`sensor` | 10s | 30s | 10s | 未知传感器不默认全部写历史 |

关键签名：

```swift
public struct TemperatureSamplingPolicy: Sendable, Equatable {
    public let realtimeInterval: TimeInterval
    public let historyInterval: TimeInterval
    public let minimumInterval: TimeInterval
    public let staleMultiplier: Double
}
```

强约束：

- `stale` 默认阈值为 `realtimeInterval * 2.5`。
- 用户设置刷新间隔只能放慢或在安全范围内调整；不能把 SSD SMART、内存、电池提高到低于各自 `minimumInterval`。
- 历史写入按照每个 probe 的 `historyInterval` 节流，实时刷新不能每次都写历史。

### `TemperatureCapabilityService`

该服务只负责能力检测和 capability 状态持久化，不负责周期采样。

```swift
public final actor TemperatureCapabilityService {
    public func detectAll(sessionID: UUID, reason: CapabilityDetectionReason) async -> [TemperatureDomain: TemperatureCapability]
}

public enum CapabilityDetectionReason: String, Sendable {
    case appStart
    case wake
    case manualRefresh
}
```

强约束：

- 启动时必须覆盖 `cpu`、`gpu`、`memory`、`ssd`、`battery`，以及已注册的 `system`/`sensor` probe。
- 单个 probe 的 `detect` 失败要转换为 `supported: true, readable: false, reasonCode: "detectFailed"` 或对应 `unsupported` capability，不能中断其他 probe。
- 唤醒后必须重检 HID、SMC、SMART 等可能失效路径，并更新 `updatedAt`。
- capability 写入失败只记录 `history.write_failed` event，不阻塞实时状态。

### `SampleBus`

`SampleBus` 是 Core 内部的轻量分发，不持有 UI 状态，也不直接访问系统 API。

```swift
public enum TemperatureSampleEvent: Sendable, Equatable {
    case samples([TemperatureSample], context: SampleContext)
    case capabilities([TemperatureDomain: TemperatureCapability], reason: CapabilityDetectionReason)
    case gap(TimelineEvent)
}

public struct SampleContext: Sendable, Equatable {
    public let sessionID: UUID
    public let probeID: String
    public let sampledAt: Date
    public let shouldWriteHistory: Bool
}
```

强约束：

- `samples` 事件先进入 `LiveTemperatureStore`，再进入历史写入订阅者；历史失败不得回滚实时状态。
- `gap` 事件必须进入历史 timeline，并让趋势查询能断线。
- 不引入全局单例；`MacWatchRuntime` 或 Core composition root 显式持有 bus。

### `LiveTemperatureStore`

`LiveTemperatureStore` 维护当前状态和 stale 判定；UI 只读该 store 暴露的 state。

```swift
public final actor LiveTemperatureStore {
    public func apply(_ event: TemperatureSampleEvent) async -> LiveTemperatureState
    public func markStale(now: Date) async -> LiveTemperatureState
    public func currentState() async -> LiveTemperatureState
}
```

状态规则：

- 最高温只从 `quality == .valid` 且 `valueCelsius != nil` 的样本计算。
- `unsupported`、`readFailed`、`stale` 不参与最高温。
- `stale` 不能覆盖最后失败原因；state 需要保留当前展示状态和最后一次成功时间。
- 同一 `metricName` 的新样本覆盖当前样本；不同 domain 不互相影响。
- 没有有效温度时，菜单栏显示短状态，例如 `--°C` 或 `CPU unavailable`，不能显示 `0°C`。

### 异常温度过滤

异常过滤应放在 Core 可测位置，StatsAdapter 也可预先丢弃明显非法 raw reading，但进入 `valid` 前必须经过统一验证。

```swift
public enum TemperatureReadingValidator {
    public static func isValidCelsius(_ value: Double) -> Bool
}
```

边界规则：

```swift
value.isFinite && value >= 0 && value <= 110
```

执行阶段需要把小于 `0°C` 或大于 `110°C` 的 raw reading 转换为 `readFailed` 或丢弃并在该 domain 无有效读数时返回 `readFailed` 样本；不能写入 `valid`，也不能进入历史有效曲线。

### `TemperatureScheduler`

调度器负责周期、暂停、恢复、stale tick 和历史节流。

```swift
public final actor TemperatureScheduler {
    public func start(sessionID: UUID) async
    public func pause(reason: SchedulerPauseReason, at timestamp: Date) async
    public func resume(reason: SchedulerResumeReason, at timestamp: Date) async
    public func stop(at timestamp: Date) async
}
```

强约束：

- 每个 probe 独立追踪 `nextRealtimeAt`、`nextHistoryAt` 和连续失败次数。
- 允许多个 probe 同一 tick 到期，但单个 probe 读取失败不能阻塞其他 probe。
- 睡眠开始：暂停所有任务，记录 `system.sleep.started`，不补造睡眠期间样本。
- 唤醒结束：记录 `system.sleep.ended`，执行能力重检，再安排下一次采样。
- 连续读取失败达到 stale 阈值时，发布 `stale` 状态和 `probe.stale` timeline event。
- 调度实现必须可被单元测试驱动；测试中不能依赖真实 `Timer` 等待数十秒。

## 实施任务

### Task 1: 固化阶段 4 策略与异常温度验证

**Files:**
- Create: `Sources/MacWatchCore/Temperature/TemperatureSamplingPolicy.swift`
- Create: `Sources/MacWatchCore/Temperature/TemperatureReadingValidator.swift`
- Test: `Tests/MacWatchCoreTests/TemperatureReadingValidatorTests.swift`

- [ ] **Step 1: 写失败测试**

测试覆盖默认策略表、SSD 最低间隔和异常温度边界。关键样例：

```swift
XCTAssertTrue(TemperatureReadingValidator.isValidCelsius(0))
XCTAssertTrue(TemperatureReadingValidator.isValidCelsius(110))
XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(-0.1))
XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(110.1))
XCTAssertFalse(TemperatureReadingValidator.isValidCelsius(.nan))
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter TemperatureReadingValidatorTests`

Expected: 编译失败或测试失败，提示新类型尚未实现。

- [ ] **Step 3: 实现最小策略和 validator**

实现 `TemperatureSamplingPolicy.default(for:)`，严格按本计划的采样策略表返回 interval。不要从 UI 设置直接覆盖 `minimumInterval`。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter TemperatureReadingValidatorTests`

Expected: 所有 validator 和默认策略测试通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MacWatchCore/Temperature/TemperatureSamplingPolicy.swift Sources/MacWatchCore/Temperature/TemperatureReadingValidator.swift Tests/MacWatchCoreTests/TemperatureReadingValidatorTests.swift
git commit -m "feat: add temperature sampling policy"
```

### Task 2: 实现 `SampleBus` 事件分发契约

**Files:**
- Create: `Sources/MacWatchCore/Temperature/SampleBus.swift`
- Test: `Tests/MacWatchCoreTests/SampleBusTests.swift`

- [ ] **Step 1: 写失败测试**

测试需要覆盖：

- 多个 subscriber 都收到同一个 `samples` 事件。
- 其中一个 subscriber 抛错或记录失败不阻断其他 subscriber。
- `gap` 事件能按顺序分发。

关键断言：

```swift
XCTEqual(receivedEvents.map(\.kind), [.samples, .gap])
XCTEqual(secondSubscriberReceived.count, 2)
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter SampleBusTests`

Expected: 编译失败或测试失败，提示 `SampleBus` 类型不存在。

- [ ] **Step 3: 实现最小 bus**

实现显式 `subscribe` 和 `publish`；不要使用全局单例，不要让 bus 访问 `SessionHistoryRepository` 或 UI。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter SampleBusTests`

Expected: 分发、错误隔离和事件顺序测试通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MacWatchCore/Temperature/SampleBus.swift Tests/MacWatchCoreTests/SampleBusTests.swift
git commit -m "feat: add temperature sample bus"
```

### Task 3: 实现 `LiveTemperatureStore`

**Files:**
- Create: `Sources/MacWatchCore/Temperature/LiveTemperatureStore.swift`
- Modify: `Sources/MacWatchCore/Temperature/LiveTemperatureState.swift`
- Test: `Tests/MacWatchCoreTests/LiveTemperatureStoreTests.swift`

- [ ] **Step 1: 写失败测试**

测试覆盖：

- `valid` CPU 样本进入当前状态并成为最高温。
- `unsupported` 和 `readFailed` 不参与最高温。
- 超过 `realtimeInterval * 2.5` 后标记 `stale`。
- `stale` 后仍可追踪最后一次 `valid` 样本时间。

关键断言：

```swift
XCTEqual(state.hottestValidSample?.metricName, TemperatureMetricName.cpuHottest)
XCTEqual(state.samplesByMetricName[TemperatureMetricName.gpuHottest]?.quality, .unsupported)
XCTEqual(staleState.samplesByMetricName[TemperatureMetricName.cpuHottest]?.quality, .stale)
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter LiveTemperatureStoreTests`

Expected: 编译失败或测试失败，提示 store 尚未实现或 state 字段不足。

- [ ] **Step 3: 实现 store 与 state 扩展**

在 `LiveTemperatureState` 中只增加 UI 和 stale 必需的只读字段，例如 `lastValidSamplesByMetricName`、`lastUpdatedAtByMetricName` 或等价结构。避免把 repository、probe 或 timer 放入 state。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter LiveTemperatureStoreTests`

Expected: 最高温、状态覆盖、stale 和最后有效样本测试通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MacWatchCore/Temperature/LiveTemperatureStore.swift Sources/MacWatchCore/Temperature/LiveTemperatureState.swift Tests/MacWatchCoreTests/LiveTemperatureStoreTests.swift
git commit -m "feat: add live temperature store"
```

### Task 4: 实现 `TemperatureCapabilityService`

**Files:**
- Create: `Sources/MacWatchCore/Temperature/TemperatureCapabilityService.swift`
- Test: `Tests/MacWatchCoreTests/TemperatureCapabilityServiceTests.swift`

- [ ] **Step 1: 写失败测试**

测试覆盖：

- 启动检测会调用所有 probe 的 `detect`。
- 单个 probe detect 失败转换成 capability，不影响其他 domain。
- 检测结果写入 repository；写入失败记录 `history.write_failed`，但仍返回 capability state。
- 唤醒 reason 会更新 `updatedAt`。

关键断言：

```swift
XCTEqual(Set(capabilities.keys), Set([.cpu, .gpu, .memory, .ssd, .battery]))
XCTEqual(capabilities[.ssd]?.reasonCode, "detectFailed")
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter TemperatureCapabilityServiceTests`

Expected: 编译失败或测试失败，提示服务尚未实现。

- [ ] **Step 3: 实现能力检测服务**

服务持有 `[any TemperatureProbe]`、`SessionHistoryRepository` 和 clock。写入失败通过 `TimelineEventType.historyWriteFailed` 记录；probe 检测失败生成 readable false 的 capability。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter TemperatureCapabilityServiceTests`

Expected: 全量检测、失败隔离、持久化和唤醒重检测试通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MacWatchCore/Temperature/TemperatureCapabilityService.swift Tests/MacWatchCoreTests/TemperatureCapabilityServiceTests.swift
git commit -m "feat: add temperature capability service"
```

### Task 5: 实现 CPU 纵切调度器

**Files:**
- Create: `Sources/MacWatchCore/Temperature/TemperatureScheduler.swift`
- Modify: `Sources/MacWatchCore/Temperature/TemperatureMonitorService.swift`
- Test: `Tests/MacWatchCoreTests/TemperatureSchedulerTests.swift`

- [ ] **Step 1: 写失败测试**

先只用 CPU fake probe 验证端到端纵切：

- `start` 后先执行能力检测，再读取 CPU。
- CPU 实时 tick 每 5 秒发布到 `SampleBus`。
- CPU 历史写入每 10 秒触发一次，不随每次实时刷新写入。
- CPU `valid` 样本进入 live store 和 repository。

关键断言：

```swift
XCTEqual(cpuProbe.readCount, 3)
XCTEqual(repository.samples(sessionID: sessionID).filter { $0.metricName == TemperatureMetricName.cpuHottest }.count, 2)
XCTEqual(liveState.hottestValidSample?.valueCelsius, 62)
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter TemperatureSchedulerTests/testCPUEndToEndSchedulesRealtimeAndHistorySeparately`

Expected: 编译失败或测试失败，提示 scheduler 尚未实现。

- [ ] **Step 3: 实现可测试 scheduler tick**

执行阶段优先实现可控 clock/tick API，再在 App 层接真实 timer。调度器内部每个 probe 维护实时和历史两个到期时间，CPU 策略使用 5s/10s。

- [ ] **Step 4: 运行 CPU 纵切测试并确认通过**

Run: `swift test --filter TemperatureSchedulerTests/testCPUEndToEndSchedulesRealtimeAndHistorySeparately`

Expected: CPU 能力检测、实时状态、历史写入和最高温均通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MacWatchCore/Temperature/TemperatureScheduler.swift Sources/MacWatchCore/Temperature/TemperatureMonitorService.swift Tests/MacWatchCoreTests/TemperatureSchedulerTests.swift
git commit -m "feat: schedule cpu temperature sampling"
```

### Task 6: 横向扩展 GPU、内存、SSD/NAND、电池和系统传感器策略

**Files:**
- Modify: `Sources/MacWatchCore/Temperature/TemperatureScheduler.swift`
- Modify: `Sources/StatsAdapter/Probes/StatsTemperatureProbeFactory.swift`
- Test: `Tests/MacWatchCoreTests/TemperatureSchedulerTests.swift`
- Test: `Tests/StatsAdapterTests/DomainTemperatureProbeTests.swift`

- [ ] **Step 1: 写失败测试**

测试覆盖：

- GPU 使用 5s/10s。
- 内存、SSD、电池使用 30s/60s。
- 系统传感器使用 10s/30s。
- SSD SMART 不因用户刷新设置低于 30s。
- 不可读 domain 仍发布 `unsupported` 或 `readFailed`，不从状态中消失。

关键断言：

```swift
XCTEqual(policy(for: .ssd, userRealtime: 5).realtimeInterval, 30)
XCTEqual(policy(for: .gpu, userRealtime: 5).historyInterval, 10)
XCTEqual(liveState.samplesByMetricName[TemperatureMetricName.ssdInternal]?.quality, .readFailed)
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter TemperatureSchedulerTests`

Expected: 新增多 domain 策略测试失败。

- [ ] **Step 3: 扩展调度策略和 probe 注册**

保留 CPU 纵切通过的路径，按 domain 使用 `TemperatureSamplingPolicy.default(for:)`。如果系统传感器 probe 尚未实现，阶段 4 可以通过已识别 `system`/`sensor` probe 注册点和 fake tests 固化调度契约，真实采集在后续横向 probe 中接入。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter TemperatureSchedulerTests`

Expected: 所有 domain 的实时间隔、历史间隔、最低安全间隔和不可读状态测试通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MacWatchCore/Temperature/TemperatureScheduler.swift Sources/StatsAdapter/Probes/StatsTemperatureProbeFactory.swift Tests/MacWatchCoreTests/TemperatureSchedulerTests.swift Tests/StatsAdapterTests/DomainTemperatureProbeTests.swift
git commit -m "feat: schedule all temperature domains"
```

### Task 7: 处理睡眠、唤醒、暂停和数据缺口

**Files:**
- Modify: `Sources/MacWatchCore/Temperature/TemperatureScheduler.swift`
- Modify: `Sources/MacWatchCore/Lifecycle/AppLifecycleCoordinator.swift`
- Test: `Tests/MacWatchCoreTests/TemperatureSchedulerTests.swift`
- Test: `Tests/MacWatchCoreTests/AppLifecycleCoordinatorTests.swift`

- [ ] **Step 1: 写失败测试**

测试覆盖：

- `pause(.systemSleep)` 记录 `system.sleep.started`，停止采样。
- 睡眠期间 tick 不产生样本，不补造数据。
- `resume(.systemWake)` 记录 `system.sleep.ended`，调用 `TemperatureCapabilityService.detectAll(reason: .wake)`。
- 唤醒后下一次采样恢复并写入新样本。
- 趋势查询返回 gap event，UI 可断线。

关键断言：

```swift
XCTEqual(events.map(\.eventType), [.systemSleepStarted, .systemSleepEnded])
XCTEqual(samplesDuringSleep.count, 0)
XCTEqual(capabilityService.detectReasons, [.appStart, .wake])
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter TemperatureSchedulerTests/testSleepPauseRecordsGapAndWakeRedetectsCapabilities`

Expected: 睡眠/唤醒行为测试失败。

- [ ] **Step 3: 实现生命周期桥接**

Core 层只处理抽象事件；App 层再把 `NSWorkspace.willSleepNotification`、`NSWorkspace.didWakeNotification` 和退出事件转成 `AppLifecycleEvent`。不要在 Core 直接依赖 AppKit。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter TemperatureSchedulerTests`

Expected: 睡眠暂停、唤醒重检、数据缺口和恢复采样测试通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MacWatchCore/Temperature/TemperatureScheduler.swift Sources/MacWatchCore/Lifecycle/AppLifecycleCoordinator.swift Tests/MacWatchCoreTests/TemperatureSchedulerTests.swift Tests/MacWatchCoreTests/AppLifecycleCoordinatorTests.swift
git commit -m "feat: handle sleep wake temperature gaps"
```

### Task 8: 替换 App 侧 fast/slow Timer 并接入 UI 当前状态

**Files:**
- Modify: `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift`
- Modify: `Sources/MacWatchApp/MenuBar/MenuBarController.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureTrendView.swift`
- Test: `Tests/MacWatchAppTests/MacWatchRuntimeSchedulerTests.swift`
- Test: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`

- [ ] **Step 1: 写失败测试**

测试覆盖：

- `MacWatchRuntime.start()` 创建 scheduler 并触发启动能力检测。
- App 不再维护 fast/slow `Timer` 行为作为采样真源。
- 菜单栏 stale 时显示弱化状态，不继续显示旧值为正常实时值。
- Popup/Dashboard 对 `unsupported`、`readFailed`、`stale` 均有可见展示数据。

关键断言：

```swift
XCTEqual(menuBarTitle(for: staleCPUState), "--°C")
XCTEqual(runtime.liveState?.capabilitiesByDomain.keys.contains(.cpu), true)
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter MacWatchRuntimeSchedulerTests`

Expected: runtime 仍依赖旧 fast/slow timer，测试失败。

- [ ] **Step 3: 接入 scheduler 和 live store**

`MacWatchRuntime` 作为 composition root 创建 repository、probe factory、capability service、sample bus、live store 和 scheduler。UI 订阅 runtime 暴露的 `LiveTemperatureState`；趋势仍通过 session repository 查询。

- [ ] **Step 4: 运行 App 层测试并确认通过**

Run: `swift test --filter MacWatchAppTests`

Expected: runtime、菜单栏展示和 presentation 测试通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MacWatchApp/Runtime/MacWatchRuntime.swift Sources/MacWatchApp/MenuBar/MenuBarController.swift Sources/MacWatchApp/Views/TemperatureDashboardView.swift Sources/MacWatchApp/Views/TemperatureTrendView.swift Tests/MacWatchAppTests/MacWatchRuntimeSchedulerTests.swift Tests/MacWatchAppTests/TemperaturePresentationTests.swift
git commit -m "feat: connect temperature scheduler to app runtime"
```

### Task 9: 完整验证、边界扫描和真实硬件 smoke test

**Files:**
- Modify: `scripts/probe_temperature_once.sh`
- Modify: `scripts/verify_stats_boundary.sh`
- Test: `Tests/StatsAdapterTests/StatsBoundaryScriptTests.swift`
- Test: `Tests/MacWatchCoreTests/*.swift`
- Test: `Tests/MacWatchAppTests/*.swift`

- [ ] **Step 1: 运行完整单元测试**

Run: `swift test`

Expected: 所有 `MacWatchCoreTests`、`StatsAdapterTests`、`MacWatchAppTests` 通过。

- [ ] **Step 2: 运行 Stats 边界扫描**

Run: `scripts/verify_stats_boundary.sh`

Expected: 没有 Stats `Reader`、`Module`、`DB.shared`、Remote、SystemStats、Updater、LaunchAtLogin helper、privileged helper 或联网路径进入 MacWatch 默认链路。

- [ ] **Step 3: 运行真实硬件 CPU smoke test**

Run: `scripts/probe_temperature_once.sh`

Expected: 在 MacBook Air M4 验收机上至少一个 CPU 温度样本为 `valid`，且温度在 `0...110°C` 范围内。若 GPU/内存/SSD/电池不可读，应输出 `unsupported` 或 `readFailed`，不能缺失状态。

- [ ] **Step 4: 手动低能耗和恢复验收**

验证项：

- 默认配置下 CPU/GPU 不快于 5s，SSD/内存/电池不快于 30s。
- 历史写入节奏与实时刷新分离。
- 睡眠期间没有补造样本。
- 唤醒后能力重检并恢复采样。
- 趋势图对 sleep gap 断线。

- [ ] **Step 5: 提交**

```bash
git add scripts/probe_temperature_once.sh scripts/verify_stats_boundary.sh Tests/StatsAdapterTests/StatsBoundaryScriptTests.swift
git commit -m "test: verify temperature scheduling boundaries"
```

## 测试矩阵

| 层级 | 命令 | 验证重点 |
| --- | --- | --- |
| Core validator/policy | `swift test --filter TemperatureReadingValidatorTests` | 异常温度过滤、默认采样策略和最低安全间隔 |
| Core bus/store | `swift test --filter SampleBusTests && swift test --filter LiveTemperatureStoreTests` | 事件分发、最高温、状态覆盖、stale |
| Core capability/scheduler | `swift test --filter TemperatureCapabilityServiceTests && swift test --filter TemperatureSchedulerTests` | 启动检测、独立间隔、历史节流、睡眠唤醒、gap |
| App runtime/UI | `swift test --filter MacWatchAppTests` | runtime composition、菜单栏/仪表盘状态展示 |
| 全量测试 | `swift test` | SwiftPM 全 target 回归 |
| Stats 边界 | `scripts/verify_stats_boundary.sh` | 不接入禁止的 Stats 生命周期、DB、联网、helper |
| 真实硬件 smoke | `scripts/probe_temperature_once.sh` | MacBook Air M4 CPU 至少一个 `valid` 温度 |

## 验收标准

- 启动时执行完整能力检测，`cpu`、`gpu`、`memory`、`ssd`、`battery` 至少都有 capability 和当前状态路径。
- MacBook Air M4 上至少一个 CPU 温度指标为 `valid`，并能从菜单栏/Popup/Dashboard/详情趋势看到。
- GPU、内存、SSD/NAND、电池不可读时显示 `unsupported` 或 `readFailed`，不能隐藏、空白、显示 `0°C` 或沿用旧值作为正常实时值。
- CPU/GPU 实时 5 秒、历史 10 秒；内存/SSD/电池实时 30 秒、历史 60 秒；系统传感器实时 10 秒、历史 30 秒。
- SSD SMART、内存、电池等高成本 probe 不被用户刷新设置提升到低于安全间隔。
- 小于 `0°C` 或大于 `110°C` 的温度不能进入 `valid`，不能参与最高温或有效趋势。
- 睡眠期间不补造样本；唤醒后记录 gap、执行能力重检并恢复采样。
- `LiveTemperatureStore` 能正确维护当前最高温、各指标状态、更新时间、最后有效样本和 stale 状态。
- 历史写入失败不影响实时显示，必须记录 `history.write_failed` event。
- 默认运行不发起外部网络请求，不记录用户文件名、网络内容、窗口标题或进程列表。
- 不修改 `Vendor/Stats`，不接入 Stats `Reader`、`Module`、`DB.shared`、LevelDB、Remote、SystemStats、Updater、LaunchAtLogin helper 或 privileged helper。

## 风险与处理

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 调度器真实 timer 难测 | 单测不稳定、等待时间长 | Core 调度器提供可控 clock/tick；App 层只负责把真实 timer 或 lifecycle 事件转发进 Core |
| 历史写入和实时刷新混在一起 | 5s 实时刷新导致历史过密和能耗增加 | `SampleContext.shouldWriteHistory` 和 per-probe `nextHistoryAt` 强制分离 |
| SMART 或传感器枚举过频 | 能耗高、潜在系统开销大 | `minimumInterval` 不允许被用户设置突破；传感器列表只在启动、唤醒或显式刷新时重建 |
| stale 覆盖失败原因 | UI 无法解释不可用原因 | `LiveTemperatureState` 保留当前展示状态、最后有效样本和 capability/error 信息 |
| 唤醒后底层句柄失效 | 采样恢复失败 | `resume(.systemWake)` 必须触发 capability 重检，并允许 probe 自行重建 reader/client |
| 阶段 4 横向扩展影响 CPU 纵切 | MVP 硬验收回归 | Task 5 先锁定 CPU 纵切测试，Task 6 之后仍保留 CPU 纵切回归断言 |

## 执行顺序约束

1. 先完成 Task 1-5，确保 CPU 温度端到端纵切从采集到实时状态、历史和 UI 可用。
2. CPU 纵切测试和真实硬件 smoke test 通过后，再执行 Task 6 横向扩展其他 domain。
3. 睡眠/唤醒和 stale 逻辑在 Task 7 统一处理，避免各 probe 自行实现暂停恢复。
4. App Runtime 接入放在 Task 8，防止 UI 在 Core 契约稳定前绑定旧 timer 行为。
5. Task 9 是完成前必跑验证；未能在当前机器验证真实硬件温度时，必须在最终汇报中明确说明未验证项和可复现命令。
