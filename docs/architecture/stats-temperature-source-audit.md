# Stats Temperature Source Audit

## Scope

- 上游参考固定为 `Vendor/Stats` `v3.0.1`。
- `Vendor/Stats` 在 MacWatch 中保持只读。
- MacWatch 只能通过 `StatsAdapter` 迁移或包装最小只读温度读取逻辑。
- 不接入 Stats `Reader` / `Module` 生命周期，不复用 Stats 历史、通知、联网、helper 或 UI 逻辑。

## Source Audit Summary

| Stats 文件 | 可复用只读点 | 明确排除点 | 验证风险 |
| --- | --- | --- | --- |
| `Vendor/Stats/Modules/Sensors/readers.swift` | SMC 温度 key 枚举思路、Apple Silicon HID 温度过滤、CPU/GPU/SOC 平均值和最高值聚合规则 | `Reader<Sensors_List>` 生命周期、`Store.shared` 开关、IOReport power 采样、fan 相关逻辑、callback 模块体系 | HID key 命名和可读性随机型变化，必须保留 raw key 并独立做 capability |
| `Vendor/Stats/Modules/Sensors/reader.m` | `IOHIDEventSystemClient` 温度事件最小读取 shim | 直接把 Stats bridge 或整个 module 接入 MacWatch | SwiftPM 混编需要独立 clang target，不能污染 Swift target |
| `Vendor/Stats/Modules/Sensors/values.swift` | Apple Silicon SMC/HID key 到 domain 和显示名的映射线索，M4 CPU/GPU/Memory/NAND/Battery 关键 key | 电压、电流、功耗、风扇和其他非温度传感器 | key 语义并非稳定 SDK，MVP 只锁定需要的温度 key |
| `Vendor/Stats/Modules/CPU/readers.swift` | Apple Silicon 平台到 CPU SMC key list 的 fallback，`TC0D` `TC0E` `TC0F` `TC0P` `TC0H` legacy fallback | CPU 负载、进程列表、频率、IOReport 频率采样 | 某些 SMC key 在新机型会返回异常值，必须加范围过滤 |
| `Vendor/Stats/Modules/GPU/reader.swift` | `IOAccelerator` `PerformanceStatistics[\"Temperature(C)\"]` 作为 GPU 温度候选 fallback | GPU 利用率、FPS、ANE 功耗、renderer/tiler、显示或进程统计 | `Temperature(C)` 可能缺失或为 `0`，不能当成稳定主来源 |
| `Vendor/Stats/Modules/Disk/readers.swift` | 内置 NVMe SMART 温度读取、Kelvin 到 Celsius 转换、SMART capability 判断 | 容量、I/O 活动、读写总量、外接盘策略 | SMART 能力受机型和驱动限制，外接盘必须排除在 MVP 外 |
| `Vendor/Stats/Modules/Battery/readers.swift` | `AppleSmartBattery` `Temperature` 属性读取，centi-Celsius 到 Celsius 转换 | 电池容量、健康度、充放电功率、通知、进程能耗 | 台式机或无电池设备会直接不可用，必须产出 `unsupported` |
| `Vendor/Stats/SMC/smc.swift` | `AppleSMC` open/read/key info/decode/getAllKeys 只读逻辑 | `write`、`setFanMode`、`setFanSpeed`、`unlockFanControl`、`resetFanControl`、任何 helper 或写操作 | 原文件包含风扇控制 API，迁移时必须只保留只读子集 |
| `Vendor/Stats/Kit/plugins/SystemKit.swift` | Apple Silicon 平台枚举、model/chip 识别、必要 `sysctl` / IORegistry 读取线索 | `system_profiler` 资源信息、序列号采集、图标资源、非温度硬件详情 | 平台识别只允许输出机型/芯片代际，不记录序列号 |

## Domain Source Priority

| Domain | 优先来源 | 关键 raw key 或属性 | 备注 |
| --- | --- | --- | --- |
| `cpu` | HID Sensors，fallback SMC | HID `pACC MTR Temp Sensor%`、`eACC MTR Temp Sensor%`；M4 SMC `Te05` `Te09` `Te0H` `Te0S` `Tp01` `Tp05` `Tp09` `Tp0D` `Tp0V` `Tp0Y` `Tp0b` `Tp0e`；legacy `TC0D` `TC0E` `TC0F` `TC0P` `TC0H` | 阶段 3 硬验收要求至少一条 CPU `valid` |
| `gpu` | HID Sensors，fallback SMC 或 IOAccelerator | HID `GPU MTR Temp Sensor%`；M4 SMC `Tg0G` `Tg0H` `Tg1U` `Tg1k` `Tg0K` `Tg0L` `Tg0d` `Tg0e` `Tg0j` `Tg0k`；IOAccelerator `PerformanceStatistics.Temperature(C)` | IOAccelerator 只作候选 fallback |
| `memory` | SMC，候选补充 HID | M4 SMC `Tm0p` `Tm1p` `Tm2p`；M1 `Tm02` `Tm06` `Tm08` `Tm09` | 未确认语义的 HID key 必须保留原始 key，不可伪命名 |
| `ssd` | NVMe SMART，fallback SMC/HID NAND | SMART `temperature`；SMC `TH0x`；HID `NAND CH% temp` | 仅覆盖内置 SSD/NAND |
| `battery` | Battery IORegistry，fallback HID/SMC | `AppleSmartBattery.Temperature`；HID `gas gauge battery`；SMC `TB1T` `TB2T` | 无电池设备要明确 `unsupported` |
| `system` / `sensor` | HID/SMC supplemental | `SOC MTR Temp Sensor%`、`PMGR SOC Die Temp Sensor%`、`ANE MTR Temp Sensor%`、`ISP MTR Temp Sensor%` | 阶段 3 不要求全部进 UI 主链路，但允许保留为补充信息 |

## Migration Rules

1. `StatsAdapter` 只能暴露 `TemperatureSample` 和 `TemperatureCapability`，不能暴露 Stats 内部类型。
2. 所有 probe 必须独立进行 capability detection；单个来源失败不能阻断其他 domain。
3. 不可读指标必须产生 `unsupported` 或 `readFailed`，不能缺席，不能显示 `0°C`。
4. `valid` 样本必须保留 `rawKey`，或在 `attributes` 中至少保留 `rawKeys`、`ioRegistryProperty`、`smartField`、`readerError` 之一。
5. 原始温度值若为 `NaN`、负数或 `>= 110°C`，不能映射为 `valid`。
6. `StatsAdapter` 不写数据库、不发通知、不联网、不持有 UI 状态。

## Explicit Exclusions

- Stats `Reader` / `Module` 生命周期
- Stats `DB.shared`、LevelDB、短期历史策略
- `SystemStats`、Remote、MQTT、OAuth 或任何外部服务
- Updater、联网检查、外部 IP 查询
- Widget、通知、LaunchAtLogin helper
- SMC privileged helper、fan control、任何 SMC 写操作
- 进程列表、资源监控、功耗估算、FPS、频率采样

## Verification Anchors

- 文档边界由 `docs/architecture/stats-boundary.md` 约束。
- 代码边界由 `scripts/verify_stats_boundary.sh` 和 `Tests/StatsAdapterTests/StatsBoundaryScriptTests.swift` 约束。
- 真实硬件输出由阶段 3 诊断脚本补充验收记录。

## Stage 3 Acceptance Record

- 验证日期：2026-06-10
- 机器型号：`Mac16,12`
- 芯片：`Apple M4`
- macOS：`15.3`
- 验证命令：`./scripts/probe_temperature_once.sh`

结果摘要：

| Domain | 结果 | 关键来源 / raw identifier |
| --- | --- | --- |
| `cpu` | `valid` | `HID Sensors`，`rawKey=PMU tdie6`，`cpu.temperature.hottest=45.005°C`，`cpu.temperature.average=40.557°C` |
| `gpu` | `readFailed` | 当前未读到 HID/SMC/IOAccelerator 温度 |
| `memory` | `readFailed` | 当前未读到 Memory Proximity SMC key |
| `ssd` | `valid` | `NVMe SMART`，`smartField=temperature`，`ssd.temperature.internal=35.85°C` |
| `battery` | `valid` | `Battery IORegistry`，`ioRegistryProperty=Temperature`，`battery.temperature=30.32°C` |

补充结论：

- 本机 M4 在 HID 温度通道上暴露的是 `PMU tdie*` / `PMU2 tdie*`，不是计划初稿中的 `pACC MTR Temp Sensor%` / `eACC MTR Temp Sensor%`。
- 阶段 3 实现已把 `PMU tdie*` 作为 M4 CPU HID fallback 归入 CPU domain，并保留原始 `rawKey` 透明展示。
