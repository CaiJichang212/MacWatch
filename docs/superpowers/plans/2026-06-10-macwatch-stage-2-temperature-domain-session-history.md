# MacWatch 阶段 2：温度领域模型与会话历史模型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 定义 MacWatch 自己的温度数据契约和当前会话历史模型，为后续 CPU 温度端到端纵切提供稳定 Core 层接口。

**Architecture:** 阶段 2 只在 `MacWatchCore` 中固定领域模型、查询模型、会话生命周期模型、历史 repository 契约和 SQLite schema，不实现真实 HID/SMC/SMART 采集。`StatsAdapter` 只对齐 Core 的温度类型，不接入 Stats `Reader`、`DB.shared`、Remote、Updater、通知或 helper；执行顺序保持“CPU 温度纵切优先，再扩展 GPU/内存/SSD/电池”。

**Tech Stack:** Swift Package Manager, Swift, XCTest, SQLite schema contract, macOS 13 Ventura 及以上。

---

## 代码片段控制规则

本计划遵循本次任务对 `superpowers:writing-plans` 的最新规定：计划文档写清目标、架构、文件路径、接口契约、测试与验收；只在关键、易误解、强约束处放小段接口签名、schema 摘要和测试样例。整文件级业务逻辑、普通样板代码和完整组件实现应在执行阶段进入代码仓库和 PR，不在本计划中展开。

## 需求来源

- `docs/origin/MacWatch-MVP-7阶段开发任务.md`：阶段 2 任务和 CPU 纵切优先顺序。
- `docs/origin/MacWatch_MVP版需求文档.md`：温度指标、数据来源、当前会话历史、数据缺口和验收标准。
- `docs/origin/MacWatch_技术架构文档.md`：领域模型、实时状态、会话历史、查询接口、SQLite 表和 Stats 边界。
- `docs/origin/Stats复用策略.md`：`Vendor/Stats` 只读、通过 `StatsAdapter` 隔离、禁止复用 Stats UI/Remote/LevelDB。

## 阶段 2 范围

阶段 2 包含：

- 定义 `TemperatureDomain`：`cpu`、`gpu`、`memory`、`ssd`、`battery`、`system`、`sensor`。
- 定义 `TemperatureSource`：`HID Sensors`、`SMC`、`Battery IORegistry`、`NVMe SMART`、`IOReport Candidate`。
- 定义 `TemperatureQuality`：`valid`、`unsupported`、`readFailed`、`stale`。
- 定义 `TemperatureSample`、`TemperatureCapability`、`TemperatureQuery`、`TemperatureSeries`。
- 定义 `TimelineEvent` 和当前会话 `MonitoringSession`。
- 实现 App 启动创建新 session、默认清理上一会话趋势数据的 Core 层语义。
- 设计 SQLite 表：`monitoring_session`、`temperature_sample`、`temperature_capability`、`timeline_event`。
- 补充模型、会话生命周期、schema 和 Stats 边界测试。

阶段 2 不包含：

- 不读取真实温度。
- 不实现 `TemperatureProbe`、`TemperatureScheduler`、`LiveTemperatureStore`。
- 不迁移 Stats HID/SMC/Battery/NVMe 读取逻辑。
- 不实现趋势图 UI、Dashboard、Popup 温度列表。
- 不引入长期跨会话历史。
- 不修改 `Vendor/Stats`。
- 不接入 Stats `Reader`、`Module` 生命周期、`DB.shared`、LevelDB、Remote、SystemStats、Updater、通知、Widget、LaunchAtLogin helper、SMC privileged helper 或 SMC 写操作。

## 目标文件结构

```text
Sources/
  MacWatchCore/
    Temperature/
      TemperatureDomain.swift
      TemperatureSource.swift
      TemperatureQuality.swift
      TemperatureSample.swift
      TemperatureCapability.swift
      TemperatureQuery.swift
      TemperatureSeries.swift
    History/
      MonitoringSession.swift
      TimelineEvent.swift
      SessionHistoryRepository.swift
      InMemorySessionHistoryRepository.swift
      SessionLifecycleService.swift
    Storage/
      SQLiteSchema.swift
  StatsAdapter/
    StatsReadOnlySource.swift
    StatsAdapterBoundary.swift
Tests/
  MacWatchCoreTests/
    TemperatureModelTests.swift
    SessionLifecycleServiceTests.swift
    SQLiteSchemaTests.swift
  StatsAdapterTests/
    StatsAdapterBoundaryTests.swift
```

## 接口契约

### 温度枚举契约

枚举 raw value 是跨层协议：UI、历史、SQLite 和 adapter 必须保持一致。`TemperatureSource` 的 raw value 使用用户可见名称，不能改成内部缩写。

```swift
public enum TemperatureDomain: String, CaseIterable, Codable, Sendable {
    case cpu, gpu, memory, ssd, battery, system, sensor
}

public enum TemperatureSource: String, CaseIterable, Codable, Sendable {
    case hidSensors = "HID Sensors"
    case smc = "SMC"
    case batteryIORegistry = "Battery IORegistry"
    case nvmeSMART = "NVMe SMART"
    case ioReportCandidate = "IOReport Candidate"
}

public enum TemperatureQuality: String, CaseIterable, Codable, Sendable {
    case valid, unsupported, readFailed, stale
}
```

强约束：

- `TemperatureSource` 本阶段只包含上述 5 个来源；`IORegistry` 不能作为独立 raw value 混入，电池路径统一归入 `Battery IORegistry`。
- `valid` 样本必须有 `valueCelsius`。
- `unsupported`、`readFailed`、`stale` 样本不得带有效温度值。
- 内部温度统一摄氏度，UI 层之后再做单位转换。

### 样本与能力契约

关键字段如下，执行阶段可按 Swift 文件拆分实现，避免把多个模型塞进一个大文件。

```swift
public struct TemperatureSample: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let metricName: String
    public let domain: TemperatureDomain
    public let deviceID: String
    public let displayName: String
    public let valueCelsius: Double?
    public let source: TemperatureSource
    public let quality: TemperatureQuality
    public let rawKey: String?
    public let errorCode: String?
    public let attributes: [String: String]
}
```

`metricName` 必须稳定，先预留以下 MVP 主指标名：

| Domain | 主指标名 | 说明 |
| --- | --- | --- |
| `cpu` | `cpu.temperature.hottest` | CPU 纵切优先使用，MacBook Air M4 验收必须读到 `valid` |
| `gpu` | `gpu.temperature.hottest` | 支持时展示 |
| `memory` | `memory.temperature.proximity` | 内存或 Memory Proximity |
| `ssd` | `ssd.temperature.internal` | 只覆盖内置 SSD/NAND |
| `battery` | `battery.temperature` | 电池温度 |
| `system` | `system.temperature.hottest` | SOC、环境、机身或系统温度 |
| `sensor` | `sensor.temperature.raw` | 无法确认语义的原始温度传感器 |

### 查询与序列契约

趋势查询必须返回样本和缺口事件，UI 之后据此断开曲线。

```swift
public struct TemperatureQuery: Equatable, Sendable {
    public let sessionID: UUID
    public let domains: [TemperatureDomain]
    public let metricNames: [String]?
    public let start: Date
    public let end: Date
    public let maxPoints: Int
}

public struct TemperatureSeries: Equatable, Sendable {
    public let metricName: String
    public let domain: TemperatureDomain
    public let samples: [TemperatureSample]
    public let gaps: [TimelineEvent]
}
```

边界规则：

- `start <= end`，否则查询构造或 repository 查询返回明确错误。
- `maxPoints` 必须大于 `0`。
- repository 不跨 `TimelineEvent` 缺口补点，不用前值填充。
- 超过约 2,000 点的降采样在阶段 5 实现，本阶段只保留 `maxPoints` 契约和测试。

### 当前会话契约

`MonitoringSession` 表示本次 App 运行会话。阶段 2 的核心行为是：收到 `.launched` 时创建新 session，并默认清理上一会话趋势数据。

```swift
public struct MonitoringSession: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public let appVersion: String?
    public let model: String?
    public let chip: String?
    public let osVersion: String?
}
```

`SessionLifecycleService` 负责把阶段 1 的 `AppLifecycleEvent` 转换为历史语义：

- `.launched`：清理非当前 session 的趋势数据，创建并保存新 `MonitoringSession`，记录 `app.started`。
- `.willSleep`：记录未结束的 `system.sleep.started`。
- `.didWake`：结束最近一次睡眠事件，记录 `system.sleep.ended`。
- `.willTerminate`：设置当前 session 的 `endedAt`，记录 `app.terminating`。

### SQLite schema 契约

阶段 2 先提交 schema 契约，不强制引入第三方 SQLite driver；真实 SQLite repository 可在阶段 5 落地。schema 必须与领域模型字段一一对应。

| Table | 关键列 |
| --- | --- |
| `monitoring_session` | `id`, `started_at_ms`, `ended_at_ms`, `app_version`, `model`, `chip`, `os_version`, `created_at_ms` |
| `temperature_sample` | `id`, `session_id`, `timestamp_ms`, `metric_name`, `domain`, `device_id`, `display_name`, `value_celsius`, `source`, `quality`, `raw_key`, `error_code`, `attributes_json`, `created_at_ms` |
| `temperature_capability` | `id`, `session_id`, `domain`, `source`, `supported`, `readable`, `reason_code`, `reason_message`, `raw_key`, `detected_at_ms`, `updated_at_ms` |
| `timeline_event` | `id`, `session_id`, `event_type`, `started_at_ms`, `ended_at_ms`, `domain`, `metric_name`, `reason_code`, `message`, `created_at_ms` |

必须包含索引：

```sql
CREATE INDEX idx_temperature_sample_session_metric_time
ON temperature_sample(session_id, metric_name, timestamp_ms);

CREATE INDEX idx_temperature_sample_session_domain_time
ON temperature_sample(session_id, domain, timestamp_ms);

CREATE INDEX idx_temperature_capability_session_domain
ON temperature_capability(session_id, domain);

CREATE INDEX idx_timeline_event_session_time
ON timeline_event(session_id, started_at_ms, ended_at_ms);
```

## 任务清单

### Task 1: 温度枚举与 raw value 测试

**Files:**

- Create: `Sources/MacWatchCore/Temperature/TemperatureDomain.swift`
- Create: `Sources/MacWatchCore/Temperature/TemperatureSource.swift`
- Create: `Sources/MacWatchCore/Temperature/TemperatureQuality.swift`
- Create: `Tests/MacWatchCoreTests/TemperatureModelTests.swift`

- [ ] **Step 1: 写枚举 raw value 测试**

  测试必须锁定所有 raw value，防止后续 UI、SQLite 和 adapter 合约被无意改坏。

  ```swift
  XCTAssertEqual(TemperatureDomain.allCases.map(\.rawValue), [
      "cpu", "gpu", "memory", "ssd", "battery", "system", "sensor"
  ])
  XCTAssertEqual(TemperatureSource.allCases.map(\.rawValue), [
      "HID Sensors", "SMC", "Battery IORegistry", "NVMe SMART", "IOReport Candidate"
  ])
  XCTAssertEqual(TemperatureQuality.allCases.map(\.rawValue), [
      "valid", "unsupported", "readFailed", "stale"
  ])
  ```

- [ ] **Step 2: 运行测试确认失败**

  Run: `swift test --filter TemperatureModelTests`

  Expected: 因类型尚不存在而失败。

- [ ] **Step 3: 实现三个枚举**

  按“接口契约”中的签名实现，保留 `public`、`CaseIterable`、`Codable`、`Sendable`。

- [ ] **Step 4: 运行测试确认通过**

  Run: `swift test --filter TemperatureModelTests`

  Expected: `TemperatureModelTests` 通过。

### Task 2: 温度样本、能力、查询和序列模型

**Files:**

- Create: `Sources/MacWatchCore/Temperature/TemperatureSample.swift`
- Create: `Sources/MacWatchCore/Temperature/TemperatureCapability.swift`
- Create: `Sources/MacWatchCore/Temperature/TemperatureQuery.swift`
- Create: `Sources/MacWatchCore/Temperature/TemperatureSeries.swift`
- Modify: `Tests/MacWatchCoreTests/TemperatureModelTests.swift`

- [ ] **Step 1: 写样本质量不变量测试**

  测试覆盖：`valid` 必须带值，非 `valid` 不得带值。执行阶段可通过 throwing initializer 或 static factory 表达此约束，避免直接 public memberwise 初始化绕过规则。

  ```swift
  XCTAssertNoThrow(try TemperatureSample.makeValid(valueCelsius: 42.5, metricName: "cpu.temperature.hottest"))
  XCTAssertThrowsError(try TemperatureSample.makeInvalid(quality: .valid, valueCelsius: nil))
  XCTAssertThrowsError(try TemperatureSample.makeInvalid(quality: .unsupported, valueCelsius: 42.5))
  ```

- [ ] **Step 2: 写查询边界测试**

  覆盖 `start <= end` 和 `maxPoints > 0`。错误类型固定为 `TemperatureModelError.invalidQuery`，便于后续 UI 做明确状态展示。

- [ ] **Step 3: 实现模型和最小校验入口**

  实现字段与“接口契约”一致。`TemperatureCapability` 字段包括 `id`、`sessionID`、`domain`、`source`、`supported`、`readable`、`reasonCode`、`reasonMessage`、`rawKey`、`detectedAt`。

- [ ] **Step 4: 运行模型测试**

  Run: `swift test --filter TemperatureModelTests`

  Expected: 样本质量、查询边界和 Codable round-trip 测试通过。

### Task 3: timeline event 与当前 session 模型

**Files:**

- Create: `Sources/MacWatchCore/History/MonitoringSession.swift`
- Create: `Sources/MacWatchCore/History/TimelineEvent.swift`
- Create: `Sources/MacWatchCore/History/SessionHistoryRepository.swift`
- Create: `Sources/MacWatchCore/History/InMemorySessionHistoryRepository.swift`
- Create: `Tests/MacWatchCoreTests/SessionLifecycleServiceTests.swift`

- [ ] **Step 1: 写 session 创建与清理测试**

  测试表达阶段 2 最重要的会话语义：启动新 session 时，上一会话趋势样本不再参与当前查询。

  ```swift
  let repository = InMemorySessionHistoryRepository()
  let service = SessionLifecycleService(repository: repository, clock: fixedClock)

  let first = try service.handle(.launched)
  try repository.insert(sampleFor: first.id, metricName: "cpu.temperature.hottest")
  let second = try service.handle(.launched)

  XCTAssertNotEqual(first.id, second.id)
  XCTAssertTrue(try repository.samples(sessionID: second.id).isEmpty)
  XCTAssertTrue(try repository.samples(sessionID: first.id).isEmpty)
  ```

- [ ] **Step 2: 写睡眠缺口事件测试**

  覆盖 `.willSleep` 生成 `system.sleep.started`，`.didWake` 结束睡眠区间并生成可供趋势断线使用的 gap。

- [ ] **Step 3: 定义 repository 协议**

  协议必须覆盖 session、sample、capability、timeline event 的写入和当前 session 查询。不要在协议中暴露 SQLite 细节。

  ```swift
  public protocol SessionHistoryRepository: AnyObject {
      func beginSession(_ session: MonitoringSession, clearingPreviousHistory: Bool) throws
      func endSession(id: UUID, endedAt: Date) throws
      func insertSample(_ sample: TemperatureSample) throws
      func insertCapability(_ capability: TemperatureCapability) throws
      func insertTimelineEvent(_ event: TimelineEvent) throws
      func query(_ query: TemperatureQuery) throws -> [TemperatureSeries]
  }
  ```

- [ ] **Step 4: 实现 `InMemorySessionHistoryRepository`**

  内存实现只服务阶段 2 单测和后续 CPU 纵切早期验证，不作为长期历史方案。它必须执行同样的清理、查询和 gap 返回语义，避免测试与真实 repository 语义分叉。

- [ ] **Step 5: 运行会话测试**

  Run: `swift test --filter SessionLifecycleServiceTests`

  Expected: session 创建、清理、终止、睡眠缺口事件测试通过。

### Task 4: SessionLifecycleService 对接阶段 1 生命周期事件

**Files:**

- Create: `Sources/MacWatchCore/History/SessionLifecycleService.swift`
- Modify: `Sources/MacWatchCore/Lifecycle/AppLifecycleCoordinator.swift`
- Modify: `Tests/MacWatchCoreTests/AppLifecycleCoordinatorTests.swift`
- Modify: `Tests/MacWatchCoreTests/SessionLifecycleServiceTests.swift`

- [ ] **Step 1: 写生命周期转发测试**

  保持阶段 1 的 `AppLifecycleCoordinator` 简洁，但允许注入 session handler。测试确认 `.launched`、`.willSleep`、`.didWake`、`.willTerminate` 都被转为历史事件。

- [ ] **Step 2: 实现最小转发接口**

  避免让 `AppLifecycleCoordinator` 直接依赖 SQLite 或 AppKit。它只记录事件，并把事件交给可选的 handler。

- [ ] **Step 3: 运行生命周期相关测试**

  Run: `swift test --filter AppLifecycleCoordinatorTests && swift test --filter SessionLifecycleServiceTests`

  Expected: 原有阶段 1 生命周期顺序测试继续通过，新 session 事件测试通过。

### Task 5: SQLite schema 契约

**Files:**

- Create: `Sources/MacWatchCore/Storage/SQLiteSchema.swift`
- Create: `Tests/MacWatchCoreTests/SQLiteSchemaTests.swift`

- [ ] **Step 1: 写 schema 测试**

  测试锁定四张表名、关键列和索引名。不要用宽松字符串包含测试掩盖缺列问题；至少逐表检查列名集合。

- [ ] **Step 2: 实现 schema 常量**

  `SQLiteSchema` 暴露 migration 版本和建表 SQL。阶段 2 只提交 schema，不绑定具体 SQLite driver。

  ```swift
  public enum SQLiteSchema {
      public static let version = 1
      public static let createStatements: [String] = allCreateTableStatements + allCreateIndexStatements
  }
  ```

- [ ] **Step 3: 运行 schema 测试**

  Run: `swift test --filter SQLiteSchemaTests`

  Expected: schema version、四张表、四个索引测试通过。

### Task 6: StatsAdapter 类型对齐与边界回归

**Files:**

- Modify: `Sources/StatsAdapter/StatsReadOnlySource.swift`
- Modify: `Sources/StatsAdapter/StatsAdapterBoundary.swift`
- Modify: `Tests/StatsAdapterTests/StatsAdapterBoundaryTests.swift`
- Keep read-only: `Vendor/Stats`

- [ ] **Step 1: 写来源映射测试**

  测试 `StatsReadOnlySource` 能映射到 Core 的 `TemperatureSource`，且不会出现 Core 契约之外的来源。

  ```swift
  XCTAssertEqual(StatsReadOnlySource.hidSensors.temperatureSource, .hidSensors)
  XCTAssertEqual(StatsReadOnlySource.smcReadOnly.temperatureSource, .smc)
  XCTAssertEqual(StatsReadOnlySource.batteryIORegistry.temperatureSource, .batteryIORegistry)
  XCTAssertEqual(StatsReadOnlySource.nvmeSMART.temperatureSource, .nvmeSMART)
  ```

- [ ] **Step 2: 实现映射**

  `StatsAdapter` 已依赖 `MacWatchCore`，因此可以 import Core 类型。不要为了映射引入 Vendor 源码 import。

- [ ] **Step 3: 跑 Stats 边界扫描**

  Run: `./scripts/verify_stats_boundary.sh`

  Expected: 不出现 Stats `Reader`、`DB.shared`、Remote、Updater、通知、helper 等禁止项进入 `Sources/`。

### Task 7: 全量验证与计划内提交点

**Files:**

- Modify only files listed in previous tasks.
- Do not modify: `Vendor/Stats/**`

- [ ] **Step 1: 运行全量测试**

  Run: `swift test`

  Expected: 所有 `MacWatchCoreTests`、`StatsAdapterTests`、`MacWatchAppTests` 通过。

- [ ] **Step 2: 运行构建**

  Run: `swift build`

  Expected: 构建成功，输出包含 `Build complete`。

- [ ] **Step 3: 运行边界检查**

  Run: `./scripts/verify_stats_boundary.sh`

  Expected: 通过；`Vendor/Stats` 未被修改；`Sources/StatsAdapter` 未接入禁止能力。

- [ ] **Step 4: 检查工作区**

  Run: `git status --short`

  Expected: 只包含阶段 2 相关源码、测试和本计划文档。

- [ ] **Step 5: 建议提交**

  ```bash
  git add Sources/MacWatchCore Sources/StatsAdapter Tests docs/superpowers/plans/2026-06-10-macwatch-stage-2-temperature-domain-session-history.md
  git commit -m "feat: define temperature domain and session history models"
  ```

## 测试与验收

阶段 2 完成标准：

- `TemperatureDomain`、`TemperatureSource`、`TemperatureQuality` raw value 与需求完全一致。
- `TemperatureSample` 能表达 `valid`、`unsupported`、`readFailed`、`stale`，且不允许非 `valid` 携带有效温度值。
- `TemperatureCapability` 能表达支持、不可读、失败原因和原始 key。
- `TemperatureQuery`、`TemperatureSeries` 能表达按 session、domain、metric、时间范围查询，并携带 gaps。
- App lifecycle 能创建新 `MonitoringSession`，默认清理上一会话趋势数据。
- 睡眠、唤醒、退出能生成 `timeline_event` 语义，趋势图后续可据此断线。
- SQLite schema 覆盖四张表和必要索引。
- `StatsAdapter` 只对齐来源类型，不读取真实 Stats 代码，不接入禁止能力。
- `swift test`、`swift build`、`./scripts/verify_stats_boundary.sh` 通过。

## 风险与控制

- **schema 与模型漂移：** 通过 `SQLiteSchemaTests` 锁定表、列和索引，后续 migration 必须显式升级 version。
- **raw value 被改坏：** 通过枚举 raw value 测试保护 UI、SQLite、adapter 的跨层协议。
- **阶段 2 过早变成采集实现：** 本计划不迁移 HID/SMC/SMART 代码，真实 CPU probe 放到阶段 3。
- **当前会话清理语义不清：** `.launched` 默认执行 `clearingPreviousHistory: true`，旧 session 样本不参与新 session 查询。
- **Stats 边界被破坏：** 每次验证运行 `./scripts/verify_stats_boundary.sh`，并保持 `Vendor/Stats` 只读。

## 自检结果

- 需求覆盖：阶段 2 列出的三个枚举、四个核心模型、当前会话模型和四张 SQLite 表均有任务覆盖。
- 代码片段控制：仅保留接口签名、测试样例、schema 摘要和关键索引；未放入整文件实现。
- 类型一致性：`sessionID`、`metricName`、`valueCelsius`、`TemperatureSource` raw value、SQLite snake_case 列名在模型、查询和 schema 中保持一致。
