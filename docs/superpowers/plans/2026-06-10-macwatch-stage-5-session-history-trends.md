# MacWatch 阶段 5：本地会话历史与趋势查询 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 MacWatch 的详情页和 Dashboard 能稳定查询本次运行会话内的温度趋势、统计摘要和数据缺口。

**Architecture:** 阶段 5 在现有 `MacWatchCore` 历史模型和阶段 4 调度链路上补齐本地会话历史存储、范围查询、统计计算、缺口返回和降采样。先完成 CPU 温度端到端纵切：CPU 采集 -> 实时状态 -> 会话历史写入 -> Dashboard/详情趋势查询；CPU 路径验证后，再把同一查询和展示能力横向扩展到 GPU、内存、SSD/NAND、电池。

**Tech Stack:** Swift Package Manager, Swift, XCTest, SQLite C API/libsqlite3, Swift Charts, SwiftUI, MacWatchCore, MacWatchApp, macOS 13 Ventura 及以上。

---

## 代码片段控制规则

本计划遵循本次任务对 `superpowers:writing-plans` 的最新规定：计划文档写清目标、架构、文件路径、接口契约、测试与验收；只在关键、易误解、强约束处放小段接口签名、测试样例、schema 摘要、降采样伪代码和边界规则。整文件级业务逻辑、普通样板代码、完整 SwiftUI 组件实现和可由测试与接口自然推导出的代码，进入执行阶段的代码仓库和 PR，不在本计划中展开。

## 需求来源

- `docs/origin/MacWatch_MVP版需求文档.md`：第 7.3、8.3、8.4、8.5、9、12 节定义趋势查看、Dashboard、详情页、本地历史、清除确认和验收标准。
- `docs/origin/MacWatch_技术架构文档.md`：第 6、8、9、16 节定义实时状态、会话历史、缺口、查询接口、SQLite 表、调度和性能验收。
- `docs/origin/Stats_功能梳理_事实版.md`：Stats `Store`/`DB` 与模块生命周期耦合，不作为 MacWatch MVP 默认历史链路。
- `docs/origin/Stats复用策略.md`：`Vendor/Stats` 只读参考，MacWatch 历史查询不复用 Stats LevelDB、`DB.shared`、Remote、SystemStats 或联网能力。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-2-temperature-domain-session-history.md`：已有领域模型、session、timeline event、query 和 schema 契约。
- `docs/superpowers/plans/2026-06-10-macwatch-stage-4-sampling-live-state-low-power.md`：已有 `TemperatureScheduler`、`SampleBus`、`LiveTemperatureStore`、历史写入节流和 gap 事件发布链路。

## 当前代码基线

当前仓库已经具备：

- `Sources/MacWatchCore/History/SessionHistoryRepository.swift`：同步 repository 协议，包含 session、sample、capability、timeline event 和 `query(_:)`。
- `Sources/MacWatchCore/History/InMemorySessionHistoryRepository.swift`：测试和早期运行使用的内存实现；当前 `limitedSamples` 只取 suffix，不满足阶段 5 的峰值保留和缺口分段降采样要求。
- `Sources/MacWatchCore/Storage/SQLiteSchema.swift`：4 张 MVP 历史表和索引的 schema 常量，但还没有真实 SQLite store。
- `Sources/MacWatchCore/Temperature/TemperatureQuery.swift`、`TemperatureSeries.swift`：已有基础查询和样本/缺口返回结构。
- `Sources/MacWatchCore/Temperature/TemperatureScheduler.swift`：已经发布 `probe.read_failed`、`probe.stale`、`system.sleep.started`、`system.sleep.ended` 等 gap event。
- `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift`：运行时已把 `SampleBus` 中 `shouldWriteHistory == true` 的样本写入 repository，并提供单一 `series(domain:metricName:window:maxPoints:)` 查询 helper。
- `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`、`TemperatureTrendView.swift`：已有 Dashboard 和基础趋势图；当前只显示默认窗口，没有范围选择、统计摘要、详情页、手动清除和清除后刷新机制。

## 阶段 5 范围

包含：

- 实现 `SessionHistoryStore` 与真实本地 `SQLiteSessionHistoryStore`。
- 保留并扩展 `SessionHistoryRepository` 作为 Core 层领域接口；UI 仍只通过 `MacWatchRuntime` 访问，不直接访问 SQLite。
- 写入并查询 `valid`、`readFailed`、`unsupported`、`stale` 样本和 timeline event。
- 实现固定范围查询：最近 15 分钟、1 小时、6 小时、全会话。
- 为查询结果计算最大值、最小值、平均值、峰值时间。
- 查询返回 `samples` 和 `gaps`，图表按 gap 分段，不能跨睡眠、读取失败、stale、history write failure 缺口连线。
- 对超过约 2,000 个点的单条序列按 gap 分段降采样，并尽量保留首尾、最小值、最大值和峰值时间。
- 实现手动清除当前会话历史，并在设置页提供二次确认。
- 先完成 CPU 纵切，再扩展 GPU、内存、SSD/NAND、电池。

不包含：

- 不做跨会话长期历史。
- 不做导出、云同步、远程监控、告警、Widget、资源监控、进程统计或风扇控制。
- 不修改 `Vendor/Stats`。
- 不复用 Stats `Reader`、`Module`、`DB.shared`、LevelDB、Remote、SystemStats、Updater、通知、LaunchAtLogin helper、privileged helper 或 SMC 写操作。
- 不把不可读取、读取失败、stale 或 unsupported 样本显示成 `0°C`、空白、旧值或估算值。

## 目标文件结构

```text
Sources/
  MacWatchCore/
    History/
      SessionHistoryRepository.swift          # 修改：补充 clear、range query、statistics 契约
      SessionHistoryStore.swift               # 新增：低层本地存储协议
      SQLiteSessionHistoryStore.swift         # 新增：SQLite C API 实现，负责 schema、CRUD 和事务
      SQLiteSessionHistoryRepository.swift    # 新增：领域 repository 实现，组合 store、query、stats、downsample
      InMemorySessionHistoryRepository.swift  # 修改：与正式 repository 契约保持一致，继续服务测试
      SessionHistoryQueryService.swift        # 新增：范围解析、gap 过滤、统计和 series 组装的可测纯逻辑
      TemperatureHistoryRange.swift           # 新增：15m、1h、6h、allSession 范围枚举
      TemperatureSeriesStatistics.swift       # 新增：max/min/average/peak time
      TemperatureSeriesDownsampler.swift      # 新增：按缺口分段降采样
    Temperature/
      TemperatureSeries.swift                 # 修改：附带 statistics，保留 samples/gaps
    Storage/
      SQLiteSchema.swift                      # 修改：必要时增加 schema version 或 pragma helper
  MacWatchApp/
    Runtime/
      MacWatchRuntime.swift                   # 修改：使用 SQLite repository，暴露 range query、clear 和 historyRevision
    Views/
      TemperatureDashboardView.swift          # 修改：展示最近 1 小时趋势摘要和进入详情的选中状态
      TemperatureDetailView.swift             # 新增：范围选择、趋势图、统计摘要、状态说明
      TemperatureTrendView.swift              # 修改：按 pre-segmented 或 gap-aware series 渲染，不跨 gap 连线
      SettingsView.swift                      # 修改：清除当前会话历史按钮和二次确认
Tests/
  MacWatchCoreTests/
    SessionHistoryStoreTests.swift
    SQLiteSessionHistoryRepositoryTests.swift
    SessionHistoryQueryServiceTests.swift
    TemperatureSeriesDownsamplerTests.swift
    TemperatureSeriesStatisticsTests.swift
  MacWatchAppTests/
    MacWatchRuntimeHistoryTests.swift
    TemperaturePresentationTests.swift
```

`Package.swift` 需要给 `MacWatchCore` target 增加 `libsqlite3` 链接：

```swift
.target(
    name: "MacWatchCore",
    linkerSettings: [
        .linkedLibrary("sqlite3")
    ]
)
```

## 接口契约

### 历史范围

`TemperatureHistoryRange` 固定 MVP 支持的 4 个范围。`allSession` 的开始时间必须使用当前 session 的 `startedAt`，不能落到上次 App 运行会话。

```swift
public enum TemperatureHistoryRange: String, CaseIterable, Codable, Sendable {
    case fifteenMinutes
    case oneHour
    case sixHours
    case allSession
}
```

范围解析规则：

| Range            | start                                       | end   |
| ---------------- | ------------------------------------------- | ----- |
| `fifteenMinutes` | `max(session.startedAt, now - 15 * 60)`     | `now` |
| `oneHour`        | `max(session.startedAt, now - 60 * 60)`     | `now` |
| `sixHours`       | `max(session.startedAt, now - 6 * 60 * 60)` | `now` |
| `allSession`     | `session.startedAt`                         | `now` |

边界规则：

- `end < session.startedAt` 时返回空序列，不抛错。
- `now` 由可注入 clock 提供，测试不得依赖真实等待。
- 默认 `maxPoints` 为 `2_000`；Dashboard 摘要可传更小值，例如 `240`。

### 统计摘要

统计只基于 `quality == .valid && valueCelsius != nil` 的样本计算。`readFailed`、`unsupported`、`stale` 样本必须保留在 `samples` 中，但不参与最大值、最小值和平均值。

```swift
public struct TemperatureSeriesStatistics: Codable, Equatable, Sendable {
    public let validSampleCount: Int
    public let maximumCelsius: Double?
    public let minimumCelsius: Double?
    public let averageCelsius: Double?
    public let peakAt: Date?
}
```

统计规则：

- 没有有效样本时，所有温度统计为 `nil`，`validSampleCount == 0`。
- 最大值并列时，`peakAt` 使用最早出现的时间。
- 平均值使用有效样本的算术平均，不按时间加权。
- UI 单位转换只发生在 `MacWatchApp` 展示层，Core 内部始终摄氏度。

### 查询结果

`TemperatureSeries` 继续返回 `samples` 和 `gaps`，阶段 5 增加 `statistics`。为了减少调用端迁移风险，初始化器应给 `statistics` 提供默认值或配套工厂。

```swift
public struct TemperatureSeries: Codable, Equatable, Sendable {
    public let metricName: String
    public let domain: TemperatureDomain
    public let samples: [TemperatureSample]
    public let gaps: [TimelineEvent]
    public let statistics: TemperatureSeriesStatistics
}
```

强约束：

- `samples` 按 `timestamp` 升序，同一时间按 `id.uuidString` 稳定排序。
- `samples` 包含有效样本和状态样本；状态样本 `valueCelsius == nil`。
- `gaps` 只包含与 query 时间范围重叠、并且与 series domain/metric 匹配或为全局 gap 的 timeline event。
- 图表断线依据 `gaps`，不是依据相邻样本时间差猜测。
- `history.cleared` 不作为趋势断线 gap；清除后旧样本已不存在，保留该 event 只用于审计或 UI 状态提示。

### Store 与 Repository

`SessionHistoryStore` 是低层本地存储协议，隐藏 SQLite 细节。`SessionHistoryRepository` 是领域接口，负责 session 当前性、范围 query、统计、降采样和清除语义。

```swift
public protocol SessionHistoryStore: AnyObject {
    func initialize() throws
    func replaceWithNewSession(_ session: MonitoringSession) throws
    func currentSession() throws -> MonitoringSession?
    func endSession(id: UUID, endedAt: Date) throws
    func insertSample(_ sample: TemperatureSample) throws
    func insertCapability(_ capability: TemperatureCapability) throws
    func insertTimelineEvent(_ event: TimelineEvent) throws
    func updateTimelineEvent(id: UUID, endedAt: Date) throws
    func samples(matching query: TemperatureQuery) throws -> [TemperatureSample]
    func timelineEvents(sessionID: UUID, start: Date, end: Date) throws -> [TimelineEvent]
    func clearHistory(sessionID: UUID, clearedAt: Date) throws
}
```

`SessionHistoryRepository` 在现有方法基础上补充：

```swift
func query(
    sessionID: UUID,
    domain: TemperatureDomain,
    metricName: String,
    range: TemperatureHistoryRange,
    now: Date,
    maxPoints: Int
) throws -> TemperatureSeries

func clearCurrentSessionHistory(at clearedAt: Date) throws
```

清除规则：

- 保留当前 `monitoring_session` 行，删除该 session 的 `temperature_sample`、`temperature_capability` 和旧 `timeline_event`。
- 删除完成后写入新的 `history.cleared` event。
- 不重置 `LiveTemperatureStore` 的当前实时状态；只清空趋势查询结果。
- 清除失败不能让 App 崩溃；`MacWatchRuntime` 捕获错误并保留当前 UI 状态。

### SQLite 行为

`SQLiteSessionHistoryStore` 必须使用事务包住 session 替换和清除操作：

```sql
BEGIN IMMEDIATE;
DELETE FROM temperature_sample;
DELETE FROM temperature_capability;
DELETE FROM timeline_event;
DELETE FROM monitoring_session;
INSERT INTO monitoring_session (...);
INSERT INTO timeline_event (... app.started ...);
COMMIT;
```

执行阶段可以按现有 `SessionLifecycleService` 语义决定 `app.started` event 仍由 service 插入，或由 `replaceWithNewSession(_:)` 插入；但只能由一个位置插入，测试必须锁定不会重复。

SQLite 约束：

- 数据库位置放在 App Support 下的 MacWatch 自有目录，例如 `Application Support/MacWatch/session-history.sqlite`。
- 每次 App 启动创建新 session 时清理上一会话历史，MVP 不跨会话查询。
- `attributes` 使用 JSON 编码为 `attributes_json`，解码失败时返回空字典并保留 sample，不让单条脏数据中断整次查询。
- 写入 invalid 状态样本时 `value_celsius` 必须为 `NULL`。
- 所有时间以 Unix epoch 毫秒入库，读取时还原为 `Date`。

### 降采样

降采样发生在每条 `TemperatureSeries` 内，且必须先按 gap 分段。不能把 gap 前后的样本放进同一个 bucket。

伪代码：

```swift
for segment in splitValidSamplesByGaps(samples, gaps) {
    if segment.count <= budgetForSegment { keep segment }
    else { keep first + perBucket(min, max, representative) + last }
}
merge segments in timestamp order
```

强约束：

- 单条 series 返回样本数不超过 `maxPoints`，默认不超过 `2_000`。
- 每个非空分段尽量保留首尾点。
- bucket 内同时保留最小值和最大值，防止峰值被平均抹掉。
- 降采样后重新按时间排序；如果同一 bucket 选中重复样本，只保留一次。
- `statistics` 基于降采样前的完整有效样本计算，不能因为降采样改变最大值、最小值、平均值和峰值时间。

## 实施任务

### Task 1: 固化范围与统计纯逻辑

**Files:**
- Create: `Sources/MacWatchCore/History/TemperatureHistoryRange.swift`
- Create: `Sources/MacWatchCore/History/TemperatureSeriesStatistics.swift`
- Create: `Sources/MacWatchCore/History/SessionHistoryQueryService.swift`
- Test: `Tests/MacWatchCoreTests/TemperatureSeriesStatisticsTests.swift`
- Test: `Tests/MacWatchCoreTests/SessionHistoryQueryServiceTests.swift`

- [ ] **Step 1: 写范围解析和统计测试**

  关键测试样例：

  ```swift
  XCTAssertEqual(
      TemperatureHistoryRange.oneHour.resolveStart(sessionStartedAt: t0, now: t0.addingTimeInterval(7200)),
      t0.addingTimeInterval(3600)
  )
  XCTAssertEqual(
      TemperatureHistoryRange.allSession.resolveStart(sessionStartedAt: t0, now: t0.addingTimeInterval(7200)),
      t0
  )
  XCTAssertEqual(stats.maximumCelsius, 81)
  XCTAssertEqual(stats.minimumCelsius, 42)
  XCTAssertEqual(stats.averageCelsius, 60, accuracy: 0.001)
  XCTAssertEqual(stats.peakAt, firstPeakTimestamp)
  ```

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter 'TemperatureSeriesStatisticsTests|SessionHistoryQueryServiceTests'`

  Expected: FAIL，类型或方法尚不存在。

- [ ] **Step 3: 实现最小范围解析和统计逻辑**

  实现重点：

  - `TemperatureHistoryRange` 只包含 4 个 MVP 范围。
  - `SessionHistoryQueryService` 作为纯逻辑，不访问 SQLite、不持有 UI 状态。
  - `TemperatureSeriesStatistics.compute(samples:)` 只使用有效样本。

- [ ] **Step 4: 运行测试**

  Run: `swift test --filter 'TemperatureSeriesStatisticsTests|SessionHistoryQueryServiceTests'`

  Expected: PASS。

- [ ] **Step 5: 提交**

  Commit message: `feat: add session history range and statistics`

### Task 2: 实现 gap-aware 降采样

**Files:**
- Create: `Sources/MacWatchCore/History/TemperatureSeriesDownsampler.swift`
- Modify: `Sources/MacWatchCore/History/SessionHistoryQueryService.swift`
- Test: `Tests/MacWatchCoreTests/TemperatureSeriesDownsamplerTests.swift`

- [ ] **Step 1: 写降采样测试**

  必测场景：

  - 2,500 个 CPU valid 样本，`maxPoints == 2_000`，返回不超过 2,000。
  - 最高温位于中间 bucket，降采样后仍能在返回 samples 中找到该峰值。
  - 睡眠 gap 前后样本不会进入同一个降采样 segment。
  - `readFailed`、`unsupported`、`stale` 样本保留状态，但图表有效点只由 valid 样本绘制。

  关键断言示例：

  ```swift
  XCTAssertLessThanOrEqual(result.samples.count, 2_000)
  XCTAssertTrue(result.samples.contains { $0.valueCelsius == 99.5 })
  XCTAssertEqual(result.gaps.map(\.eventType), [.systemSleepStarted, .probeReadFailed])
  ```

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter TemperatureSeriesDownsamplerTests`

  Expected: FAIL，downsampler 尚不存在或仍使用 suffix 截断。

- [ ] **Step 3: 实现分段降采样**

  实现重点：

  - 先用 `TimelineEvent` 把 valid 样本切成 segment。
  - 按 segment 大小分配点数预算，最小预算要能保留非空 segment 的首尾。
  - bucket 内保留 min/max，按 timestamp 去重并排序。
  - invalid 状态样本不参与线段点位，但仍在 `samples` 中保留，数量也受 `maxPoints` 总预算约束。

- [ ] **Step 4: 运行测试**

  Run: `swift test --filter TemperatureSeriesDownsamplerTests`

  Expected: PASS。

- [ ] **Step 5: 提交**

  Commit message: `feat: add gap-aware trend downsampling`

### Task 3: 扩展 Repository 契约和内存实现

**Files:**
- Modify: `Sources/MacWatchCore/History/SessionHistoryRepository.swift`
- Modify: `Sources/MacWatchCore/History/InMemorySessionHistoryRepository.swift`
- Modify: `Sources/MacWatchCore/Temperature/TemperatureSeries.swift`
- Test: `Tests/MacWatchCoreTests/SessionLifecycleServiceTests.swift`
- Test: `Tests/MacWatchCoreTests/SessionHistoryQueryServiceTests.swift`

- [ ] **Step 1: 写 repository 契约测试**

  覆盖：

  - `query(sessionID:domain:metricName:range:now:maxPoints:)` 返回统计、samples 和 gaps。
  - `clearCurrentSessionHistory(at:)` 清空当前 session 样本和旧 gap，并写入一个 `history.cleared` event。
  - gap-only 查询仍返回 series shell，便于 UI 展示缺口。

  关键断言示例：

  ```swift
  XCTAssertEqual(series.statistics.validSampleCount, 2)
  XCTAssertEqual(series.gaps.map(\.eventType), [.systemSleepStarted])
  XCTAssertTrue(series.samples.allSatisfy { $0.sessionID == session.id })
  XCTAssertEqual(eventsAfterClear.map(\.eventType), [.historyCleared])
  ```

- [ ] **Step 2: 运行现有和新增历史测试并确认失败**

  Run: `swift test --filter 'SessionLifecycleServiceTests|SessionHistoryQueryServiceTests'`

  Expected: FAIL，协议和实现尚未补齐。

- [ ] **Step 3: 修改协议、series 和内存实现**

  实现重点：

  - `TemperatureSeries` 增加 `statistics`，保持现有调用点可迁移。
  - `InMemorySessionHistoryRepository.query(_:)` 改用 `SessionHistoryQueryService`。
  - `clearCurrentSessionHistory(at:)` 保留 current session，删除内存样本、capability、旧 timeline event，然后插入 `history.cleared`。

- [ ] **Step 4: 运行历史相关测试**

  Run: `swift test --filter 'SessionLifecycleServiceTests|SessionHistoryQueryServiceTests'`

  Expected: PASS。

- [ ] **Step 5: 提交**

  Commit message: `feat: extend session history repository queries`

### Task 4: 实现 SQLite SessionHistoryStore

**Files:**
- Create: `Sources/MacWatchCore/History/SessionHistoryStore.swift`
- Create: `Sources/MacWatchCore/History/SQLiteSessionHistoryStore.swift`
- Modify: `Sources/MacWatchCore/Storage/SQLiteSchema.swift`
- Modify: `Package.swift`
- Test: `Tests/MacWatchCoreTests/SessionHistoryStoreTests.swift`
- Test: `Tests/MacWatchCoreTests/SQLiteSchemaTests.swift`

- [ ] **Step 1: 写 SQLite store 测试**

  使用临时目录数据库文件，覆盖：

  - `initialize()` 创建 4 张表和 4 个索引。
  - `replaceWithNewSession(_:)` 清理旧 session 历史并保存新 session。
  - 插入/读取 valid 和 invalid 样本，invalid 样本 `valueCelsius == nil`。
  - 插入/更新 timeline event，睡眠 event 能写入 `endedAt`。
  - `clearHistory(sessionID:clearedAt:)` 清除当前 session 历史并保留 `history.cleared`。

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter 'SessionHistoryStoreTests|SQLiteSchemaTests'`

  Expected: FAIL，SQLite store 尚不存在或未链接 `sqlite3`。

- [ ] **Step 3: 增加 sqlite3 链接并实现 store**

  实现重点：

  - 使用 `sqlite3_open_v2`、prepared statement 和绑定参数，不拼接用户数据 SQL。
  - 所有写入路径捕获 SQLite error message 并转成明确的 Swift error。
  - `attributes_json` 使用 `JSONEncoder`/`JSONDecoder`。
  - session 替换和清除使用事务；失败时 rollback。

- [ ] **Step 4: 运行 SQLite 测试**

  Run: `swift test --filter 'SessionHistoryStoreTests|SQLiteSchemaTests'`

  Expected: PASS。

- [ ] **Step 5: 提交**

  Commit message: `feat: add sqlite session history store`

### Task 5: 实现 SQLiteSessionHistoryRepository

**Files:**
- Create: `Sources/MacWatchCore/History/SQLiteSessionHistoryRepository.swift`
- Modify: `Sources/MacWatchCore/History/SessionLifecycleService.swift`
- Test: `Tests/MacWatchCoreTests/SQLiteSessionHistoryRepositoryTests.swift`
- Test: `Tests/MacWatchCoreTests/SessionLifecycleServiceTests.swift`

- [ ] **Step 1: 写 repository 集成测试**

  覆盖 CPU 纵切最小闭环：

  - 新 session 启动后写入 CPU valid 样本。
  - 写入 CPU `readFailed` 样本和 `probe.read_failed` event。
  - 查询最近 15 分钟返回 CPU series，包含 valid 和 readFailed 样本、read failure gap、统计摘要。
  - 新 session 启动后上一 session 不再参与查询。

  关键断言示例：

  ```swift
  XCTAssertEqual(series.domain, .cpu)
  XCTAssertEqual(series.metricName, TemperatureMetricName.cpuHottest)
  XCTAssertEqual(series.statistics.maximumCelsius, 72)
  XCTAssertEqual(series.gaps.map(\.eventType), [.probeReadFailed])
  XCTAssertTrue(series.samples.contains { $0.quality == .readFailed })
  ```

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter 'SQLiteSessionHistoryRepositoryTests|SessionLifecycleServiceTests'`

  Expected: FAIL，repository 尚不存在或 session 生命周期未接入 store。

- [ ] **Step 3: 实现 repository**

  实现重点：

  - repository 组合 `SessionHistoryStore` 和 `SessionHistoryQueryService`。
  - `query(_:)` 和 range query 共用同一组过滤、统计、gap 和降采样逻辑。
  - 写入失败向上抛出，由 `MacWatchRuntime` 或 scheduler 现有 `history.write_failed` 路径处理。
  - `SessionLifecycleService` 不重复插入 `app.started`。

- [ ] **Step 4: 运行 repository 测试**

  Run: `swift test --filter 'SQLiteSessionHistoryRepositoryTests|SessionLifecycleServiceTests'`

  Expected: PASS。

- [ ] **Step 5: 提交**

  Commit message: `feat: add sqlite session history repository`

### Task 6: 在 MacWatchRuntime 接入真实历史查询和清除

**Files:**
- Modify: `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift`
- Modify: `Sources/MacWatchApp/MacWatchApp.swift`
- Test: `Tests/MacWatchAppTests/MacWatchRuntimeHistoryTests.swift`
- Test: `Tests/MacWatchAppTests/MacWatchRuntimeTests.swift`

- [ ] **Step 1: 写 runtime 测试**

  覆盖：

  - 默认依赖创建 SQLite repository，测试可注入内存 repository。
  - `series(domain:metricName:range:maxPoints:)` 使用当前 session 和固定范围。
  - `clearCurrentSessionHistory()` 调用 repository 清除并递增 `historyRevision`，让 SwiftUI 重新查询。
  - 清除失败不崩溃，记录可观察错误状态或保持 UI 状态。

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter 'MacWatchRuntimeHistoryTests|MacWatchRuntimeTests'`

  Expected: FAIL，runtime 尚未暴露 range query、clear 或 history revision。

- [ ] **Step 3: 修改 runtime composition root**

  实现重点：

  - `MacWatchSharedDependencies` 创建 App Support 目录下的 SQLite store/repository。
  - 测试继续用注入式 repository，避免真实文件系统依赖。
  - `MacWatchRuntime` 新增 `@Published private(set) var historyRevision: Int`。
  - `series(...)` 支持 `TemperatureHistoryRange`，Dashboard 默认 `.oneHour`，详情默认读取设置或 `.allSession`。

- [ ] **Step 4: 运行 App runtime 测试**

  Run: `swift test --filter 'MacWatchRuntimeHistoryTests|MacWatchRuntimeTests'`

  Expected: PASS。

- [ ] **Step 5: 提交**

  Commit message: `feat: wire runtime to session history queries`

### Task 7: 完成 CPU 详情趋势 UI

**Files:**
- Create: `Sources/MacWatchApp/Views/TemperatureDetailView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureTrendView.swift`
- Test: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`

- [ ] **Step 1: 写展示层测试**

  覆盖：

  - 统计摘要格式化：最大、最小、平均、峰值时间。
  - 无有效样本但有 `readFailed` 或 `unsupported` 时显示状态，不显示 `0°C`。
  - trend view 对 gap 分段后不把 gap 前后样本作为同一条线段。

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter TemperaturePresentationTests`

  Expected: FAIL，统计格式化或分段行为尚未补齐。

- [ ] **Step 3: 实现 CPU 详情趋势**

  实现重点：

  - Dashboard 保留现有总览和最近 1 小时趋势摘要。
  - 详情区域先以 CPU 为默认选中 metric，提供 15 分钟、1 小时、6 小时、全会话 segmented picker。
  - `TemperatureTrendView` 使用 repository 返回的 `gaps` 分段，不通过时间差猜测断线。
  - 统计显示使用 Core 提供的 `TemperatureSeriesStatistics`。
  - UI 内部只调用 `runtime.series(...)`，不直接访问 SQLite、IOKit、SMC、IOReport、`Vendor/Stats`。

- [ ] **Step 4: 运行展示测试**

  Run: `swift test --filter TemperaturePresentationTests`

  Expected: PASS。

- [ ] **Step 5: 手动运行 CPU 纵切**

  Run: `swift run MacWatchApp`

  Manual expected:

  - CPU 卡片出现实时状态。
  - 等待至少 2 次 CPU 历史写入后，详情趋势能显示 CPU 曲线。
  - 切换 15 分钟、1 小时、6 小时、全会话不会崩溃。
  - 若当前机器无法真实读取 CPU 温度，UI 显示 `Read failed` 或 `Unsupported`，不显示 `0°C`。

- [ ] **Step 6: 提交**

  Commit message: `feat: show cpu session trend details`

### Task 8: 横向扩展 GPU、内存、SSD/NAND、电池趋势

**Files:**
- Modify: `Sources/MacWatchApp/Views/TemperatureDashboardView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureDetailView.swift`
- Modify: `Sources/MacWatchApp/Views/TemperatureTrendView.swift`
- Test: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`
- Test: `Tests/MacWatchCoreTests/SQLiteSessionHistoryRepositoryTests.swift`

- [ ] **Step 1: 写多 domain 查询测试**

  覆盖：

  - GPU、内存、SSD/NAND、电池各自使用 `TemperatureDashboardSnapshot.metricName(for:)` 的主指标名。
  - unsupported capability 或 unsupported sample 可以查询并展示状态。
  - SSD 和电池无 valid 样本时不参与最高温和统计。

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter 'SQLiteSessionHistoryRepositoryTests|TemperaturePresentationTests'`

  Expected: FAIL，多 domain UI 或 query 选择尚未补齐。

- [ ] **Step 3: 扩展详情选择**

  实现重点：

  - 复用 CPU 路径，不复制每个 domain 的 query 逻辑。
  - Dashboard 卡片点击切换详情 metric。
  - 不支持和读取失败的 domain 保持可见，详情页显示状态说明和空趋势。
  - SSD 仍只覆盖内置 SSD/NAND，不加入外接磁盘。

- [ ] **Step 4: 运行测试**

  Run: `swift test --filter 'SQLiteSessionHistoryRepositoryTests|TemperaturePresentationTests'`

  Expected: PASS。

- [ ] **Step 5: 提交**

  Commit message: `feat: add multi-domain session trends`

### Task 9: 实现手动清除当前会话历史

**Files:**
- Modify: `Sources/MacWatchApp/Views/SettingsView.swift`
- Modify: `Sources/MacWatchApp/Runtime/MacWatchRuntime.swift`
- Test: `Tests/MacWatchAppTests/TemperaturePresentationTests.swift`
- Test: `Tests/MacWatchAppTests/MacWatchRuntimeHistoryTests.swift`

- [ ] **Step 1: 写清除交互测试**

  覆盖：

  - 设置页存在清除当前会话历史入口。
  - 必须通过 destructive 二次确认后才调用 runtime 清除。
  - 清除后 Dashboard/详情趋势重新查询为空或只显示清除后的新样本。
  - 重置设置不触发清除历史。

- [ ] **Step 2: 运行测试并确认失败**

  Run: `swift test --filter 'MacWatchRuntimeHistoryTests|TemperaturePresentationTests'`

  Expected: FAIL，设置页尚未接入清除确认。

- [ ] **Step 3: 实现二次确认**

  macOS SwiftUI 交互约束：

  - 使用 `.alert` 或 `.confirmationDialog` 展示确认。
  - destructive action 文案明确为清除当前会话历史。
  - cancel action 不调用 repository。
  - 成功后递增 `historyRevision`，失败时保留现有趋势并展示可诊断状态。

- [ ] **Step 4: 运行测试**

  Run: `swift test --filter 'MacWatchRuntimeHistoryTests|TemperaturePresentationTests'`

  Expected: PASS。

- [ ] **Step 5: 提交**

  Commit message: `feat: add confirmed session history clearing`

### Task 10: 端到端验收和边界扫描

**Files:**
- No source file required unless verification exposes defects.
- Review: `Sources/MacWatchCore/History/*`
- Review: `Sources/MacWatchApp/Views/*`
- Review: `Sources/StatsAdapter/*`
- Review: `Vendor/Stats` only as read-only reference if a failure requires confirming source boundaries.

- [ ] **Step 1: 运行完整测试**

  Run: `swift test`

  Expected: PASS。

- [ ] **Step 2: 扫描 Stats 禁止复用边界**

  Run:

  ```bash
  rg -n "DB\\.shared|LevelDB|Remote|MQTT|OAuth|Updater|LaunchAtLogin|SystemStats|SMC.*write|privileged|Widget" Sources Tests Package.swift
  ```

  Expected: 不出现新增违禁接入；命中测试字符串时需要人工确认仅为边界测试。

- [ ] **Step 3: 验证 SQLite 数据库不包含隐私越界字段**

  检查 `SQLiteSchema.swift` 和 `SQLiteSessionHistoryStore.swift`：

  - 不记录文件路径。
  - 不记录窗口标题。
  - 不记录网络内容。
  - 不记录进程列表。
  - 不发起网络请求。

- [ ] **Step 4: 手动验收 CPU 纵切**

  Run: `swift run MacWatchApp`

  Manual expected on Apple Silicon MacBook Air target:

  - App 启动创建新 session，上次会话趋势不显示。
  - CPU 读到有效温度时，菜单栏、Dashboard、详情趋势都能看到 CPU 当前值和历史曲线。
  - 最近 15 分钟、1 小时、6 小时、全会话查询返回时间小于 1 秒。
  - 睡眠/唤醒或模拟 gap 后，图表断线，不跨 gap 连线。
  - 清除当前会话历史需要二次确认，确认后旧趋势消失，新样本继续写入。

- [ ] **Step 5: 手动验收横向 domain**

  Manual expected:

  - GPU、内存、SSD/NAND、电池支持时显示趋势和统计。
  - 不支持或读取失败时显示明确状态，不显示 `0°C` 或旧值。
  - 不支持 domain 不参与最高温统计。

- [ ] **Step 6: 提交最终修复**

  Commit message: `test: verify stage 5 session history trends`

## 测试与验收矩阵

| Requirement                                             | Test/Verification                                                 |
| ------------------------------------------------------- | ----------------------------------------------------------------- |
| 实现 `SessionHistoryStore` / `SessionHistoryRepository` | `SessionHistoryStoreTests`, `SQLiteSessionHistoryRepositoryTests` |
| 写入 valid 样本                                         | repository 集成测试插入 CPU valid 并查询                          |
| 写入读取失败状态                                        | repository 集成测试查询 `quality == .readFailed`                  |
| 写入不支持状态                                          | 多 domain 查询测试覆盖 `quality == .unsupported`                  |
| 写入 timeline event                                     | sleep/readFailed/stale/historyCleared event 测试                  |
| 15 分钟、1 小时、6 小时、全会话                         | `SessionHistoryQueryServiceTests`                                 |
| 最大、最小、平均、峰值时间                              | `TemperatureSeriesStatisticsTests`                                |
| 返回 samples 和 gaps                                    | `SQLiteSessionHistoryRepositoryTests`                             |
| 图表不跨缺口连线                                        | `TemperaturePresentationTests`, 手动 sleep/wake 验收              |
| 超过约 2,000 点降采样                                   | `TemperatureSeriesDownsamplerTests`                               |
| 手动清除当前会话历史并二次确认                          | `MacWatchRuntimeHistoryTests`, `TemperaturePresentationTests`     |
| CPU 端到端纵切优先                                      | Task 7 手动验收                                                   |
| GPU/内存/SSD/电池横向扩展                               | Task 8 和 Task 10 手动验收                                        |

## 风险与处理

- SQLite C API 容易引入资源释放遗漏：每个 prepared statement 必须 `sqlite3_finalize`，连接生命周期集中在 `SQLiteSessionHistoryStore`。
- 降采样可能丢峰值：bucket 内保留 min/max，统计基于完整样本，测试锁定峰值不丢。
- gap 断线可能在 UI 层被插值抹平：`TemperatureTrendView` 必须按 segment 创建独立 `LineMark` 序列，不用单条 series 绘制全部点。
- 清除历史后实时状态和趋势状态可能不一致：清除只影响历史 repository，`historyRevision` 触发趋势重新查询；实时温度继续来自 `LiveTemperatureStore`。
- 真实硬件温度在当前环境可能无法验证：使用 fake probe、临时 SQLite 和手动验收步骤验证 Core/UI 行为；最终 MacBook Air M4 机器上仍需确认 CPU valid 温度。

## 完成定义

阶段 5 完成需要同时满足：

- `swift test` 通过。
- CPU 从采集到详情趋势的纵切在真实或 fake probe 环境可跑通。
- Dashboard 和详情页能查询当前 session 的 15 分钟、1 小时、6 小时、全会话趋势。
- 查询结果包含 samples、gaps 和统计摘要。
- 任何 gap 不被图表跨线连接。
- 单条 series 超过约 2,000 点时降采样。
- 手动清除当前会话历史有二次确认，清除后新样本继续写入。
- 未新增 Stats 禁止链路、联网能力、长期跨会话历史、告警、导出、Widget 或风扇控制。
