建议把 MacWatch MVP 拆成 **7 个开发阶段**。当前仓库里 `Sources/MacWatchApp`、`Sources/MacWatchCore`、`Sources/StatsAdapter` 还是空目录，所以应从工程骨架和温度主链路开始，而不是先迁移大量 Stats 代码。

推荐顺序是：**先做 CPU 温度端到端纵切，再扩展 GPU/SSD/电池/系统传感器**。也就是先让“采集 CPU → 实时状态 → 会话历史 → 菜单栏/详情趋势”完整跑通，再横向补齐其他温度域。CPU/GPU 口径以 Stats Sensors 的 Hottest/Average 为准，`PMU tdie*` / `PMU2 tdie*` 不归入 CPU。

**阶段 1：工程骨架与边界确认**

目标：建立可编译、可运行、职责清晰的 macOS App 基础。

任务：

- 搭建 Swift/macOS 工程结构：`MacWatchApp`、`MacWatchCore`、`StatsAdapter`。
- 明确 `Vendor/Stats` 只读引用边界，不直接接入 Stats `Reader`、`DB.shared`、Remote、Updater、通知、helper。
- 建立 macOS 场景结构：`NSStatusItem` 菜单栏入口、SwiftUI 主窗口 `WindowGroup`、`Settings` scene。
- 建立基础 App 生命周期：启动、退出、睡眠、唤醒事件入口。
- 建立单元测试和构建脚本，保证后续阶段每步可验证。

**阶段 2：温度领域模型与会话历史模型**

目标：先把 MacWatch 自己的数据契约定稳。

任务：

- 定义 `TemperatureDomain`：`cpu`、`gpu`、`ssd`、`battery`、`system`、`sensor`。
- 定义 `TemperatureSource`：`HID Sensors`、`SMC`、`Battery IORegistry`、`NVMe SMART`、`IOReport Candidate`。
- 定义 `TemperatureQuality`：`valid`、`unsupported`、`readFailed`、`stale`。
- 定义 `TemperatureSample`、`TemperatureCapability`、`TemperatureQuery`、`TemperatureSeries`。
- 实现当前会话模型：App 启动创建新 session，默认清理上一会话趋势数据。
- 设计 SQLite 表：`monitoring_session`、`temperature_sample`、`temperature_capability`、`timeline_event`。

**阶段 3：StatsAdapter 与温度采集能力验证**

目标：打通真实温度读取，但只迁移必要的只读采集逻辑。

任务：

- 核验 Stats 相关源码：
  - `Vendor/Stats/Modules/Sensors/readers.swift`
  - `Vendor/Stats/Modules/Sensors/reader.m`
  - `Vendor/Stats/Modules/CPU/readers.swift`
  - `Vendor/Stats/Modules/GPU/reader.swift`
  - `Vendor/Stats/Modules/Disk/readers.swift`
  - `Vendor/Stats/Modules/Battery/readers.swift`
  - `Vendor/Stats/SMC/smc.swift`
  - `Vendor/Stats/Kit/plugins/SystemKit.swift`
- 实现 `TemperatureProbe` 协议。
- 实现 CPU 温度 probe，作为第一条端到端验收链路。
- 实现 GPU、SSD/NAND、电池和系统传感器温度 probe 的能力检测和读取尝试。
- 对不可读指标输出 `unsupported` 或 `readFailed`，不能静默隐藏。
- 保留原始 sensor key、SMC key、IORegistry property 或 SMART 标识。
- 明确禁止接入 Stats Remote、SystemStats、LevelDB、Updater、通知、风扇控制 helper。

**阶段 4：采样调度、实时状态与低能耗策略**

目标：让采集稳定、低成本、可恢复。

任务：

- 实现 `TemperatureCapabilityService`，启动时执行完整能力检测。
- 实现 `TemperatureScheduler`，为不同 probe 管理独立刷新间隔。
- 实现默认采样策略：
  - CPU/GPU 实时 5 秒，历史 10 秒。
  - SSD/电池实时 30 秒，历史 60 秒。
  - 系统传感器实时 10 秒，历史 30 秒。
- 实现 `SampleBus`，把采样结果分发给实时状态和历史写入。
- 实现 `LiveTemperatureStore`，维护当前最高温、各指标状态、更新时间、stale 判断。
- 处理睡眠暂停、唤醒恢复、能力重检、数据缺口事件。
- 过滤异常温度，例如小于 0°C 或大于 110°C 不进入 `valid`。

**阶段 5：本地会话历史与趋势查询**

目标：让详情页和 Dashboard 能稳定查询本次运行会话趋势。

任务：

- 实现 `SessionHistoryStore` / `SessionHistoryRepository`。
- 写入有效样本、读取失败状态、不支持状态和 timeline event。
- 实现按时间范围查询：15 分钟、1 小时、6 小时、全会话。
- 实现最大值、最小值、平均值、峰值时间计算。
- 查询结果返回 samples 和 gaps，图表不能跨睡眠或失败缺口连线。
- 对超过约 2,000 个点的查询做降采样。
- 实现手动清除当前会话历史，并做二次确认。

**阶段 6：MVP UI：菜单栏、Popup、Dashboard、详情、设置**

目标：完成用户可见的 MVP 功能闭环。

任务：

- 菜单栏：
  - 默认显示当前最高温，例如 `72°C`。
  - 支持显示最高温、CPU、GPU、磁盘、电池。
  - 支持摄氏度/华氏度。
  - stale 状态弱化显示。
- Popup：
  - 显示最高温、CPU、GPU、SSD/NAND、电池、系统温度。
  - 每项显示状态、来源、更新时间。
  - 提供打开 Dashboard 和兼容性信息入口。
- Dashboard：
  - 显示最高温卡片。
  - 显示各温度指标卡片。
  - 显示最近 1 小时趋势摘要。
  - 显示不可用指标说明。
- 详情页：
  - 显示单指标趋势图。
  - 支持 15 分钟、1 小时、6 小时、全会话。
  - 显示当前值、最高、最低、平均、峰值时间、来源、采样状态。
- 设置页：
  - 温度单位。
  - 刷新间隔：5 秒、10 秒、30 秒。
  - 默认趋势范围。
  - 菜单栏显示项。
  - 兼容性状态。
  - 清除当前会话历史。

**阶段 7：验收、性能、隐私与发布收口**

目标：确认 MVP 符合需求文档的硬性验收标准。

任务：

- 在 MacBook Air M4 上验证 CPU/GPU 只使用 Stats 认可传感器；支持时输出 Hottest/Average，当前设备不暴露对应传感器时输出 `readFailed`。
- 验证 CPU、GPU、SSD/NAND、电池和系统/传感器温度都有状态展示。
- 验证不可读指标显示 `unsupported` 或 `readFailed`，不显示 `0°C`、空白或伪造值。
- 验证菜单栏、Popup、Dashboard 打开不阻塞主线程。
- 验证 Dashboard 首屏小于 1 秒，趋势查询小于 1 秒。
- 验证默认 CPU 占用目标低于 2%，内存低于 120 MB。
- 验证睡眠唤醒后采集恢复，趋势图显示数据缺口。
- 验证首次启动和默认运行不发起外部网络请求。
- 验证没有接入 Stats Remote、SystemStats、Updater、LevelDB、通知、风扇控制 helper。
- 做 Developer ID 签名、公证、基础分发检查。
