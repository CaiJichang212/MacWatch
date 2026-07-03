# MacWatch

MacWatch 是一个面向 Apple Silicon MacBook Air 的本机温度监控工具。当前 MVP 聚焦温度主链路：采集 CPU、GPU、内置 SSD/NAND、电池、系统与原始传感器温度中可读取的指标，展示实时状态，记录本次运行会话历史，并提供趋势查看。

项目默认本地运行，不联网、不上传，不记录用户文件名、网络内容、窗口标题或进程列表。Stats 只作为只读上游参考，MacWatch 通过自己的 `StatsAdapter` 隔离必要的只读采集逻辑。

## 当前状态

当前源码已包含 MVP 主链路与阶段 7 验收收口相关能力：

- Swift Package 工程，目标平台为 macOS 13 及以上，Swift tools version 为 5.9。
- `MacWatchApp`：SwiftUI App、`AppDelegate`、菜单栏入口、Popup、Dashboard、兼容性页、温度详情页、设置页、首次启动引导、运行时组装和验收 CLI。
- `MacWatchCore`：温度领域模型、读数校验、能力检测、采样调度、`SampleBus`、实时状态、设置、本次运行会话生命周期、SQLite 会话历史、趋势查询、统计和降采样。
- `StatsAdapter`：CPU、GPU、SSD/NAND、电池、系统温度和原始传感器温度 probe；只读 HID、SMC、IORegistry、IOAccelerator、NVMe SMART 等适配代码。
- `StatsAdapterIOHID`：最小 Objective-C HID Sensors 只读桥接 target。
- `Tests`：Core、App、StatsAdapter 单元测试，以及 Stats 边界、阶段 7 脚本和验收 CLI 相关测试。
- `scripts/run_stage7_acceptance.sh`：阶段 7 验收入口，覆盖 probe 状态、Dashboard、Popup、首次启动、启动时主窗口设置、趋势查询、睡眠唤醒模拟、资源、网络、Stats 边界和分发预检。

当前温度指标名包括：

- `cpu.temperature.hottest`、`cpu.temperature.average`
- `gpu.temperature.hottest`、`gpu.temperature.average`
- `ssd.temperature.internal`
- `battery.temperature`
- `system.temperature.hottest`
- `sensor.temperature.raw`

设置项包括：启动时打开主窗口、温度单位（摄氏/华氏）、刷新间隔（5/10/30 秒）、默认趋势范围、菜单栏显示指标（最热/CPU/GPU/SSD/电池）。历史数据限定为本次 App 运行会话；SQLite 文件由 App 写入用户 Application Support 下的 `MacWatch/session-history.sqlite`，初始化失败时退回内存仓库。

硬件实测能力取决于运行机器和 macOS 暴露的系统接口。不可读指标必须显示为 `unsupported`、`readFailed` 或 `stale`，不能显示为 `0°C`、空白、旧值或估算值。

## 项目结构

```text
MacWatch/
  Package.swift
  Sources/
    MacWatchApp/          # App 入口、菜单栏、窗口、Popup、设置、SwiftUI 展示层和验收 CLI
    MacWatchCore/         # 领域模型、采样调度、实时状态、会话历史、设置和核心业务逻辑
    StatsAdapter/         # Stats 可复用只读采集逻辑的隔离适配层
    StatsAdapterIOHID/    # HID Sensors 最小只读桥接
  Tests/
    MacWatchAppTests/
    MacWatchCoreTests/
    StatsAdapterTests/
  Vendor/
    Stats/                # 只读上游源码参考，固定为 submodule
  docs/
    origin/               # 需求、架构和 Stats 复用来源文档
    architecture/         # 架构边界和审计文档
    superpowers/plans/    # 阶段计划
  scripts/                # 构建、测试、打包、运行、验收和边界扫描脚本
```

## 环境要求

- macOS 13 Ventura 或以上。
- Apple Silicon MacBook Air 是 MVP 验收目标；其他 Mac 只能按运行时能力检测结果兼容。
- Xcode Command Line Tools。
- Swift 5.9 toolchain。
- 已初始化 `Vendor/Stats` submodule。
- 如需启用 OpenSpec，需要 Node.js 20.19.0 或以上，以及可用的 `npm`。

初始化 submodule：

```bash
git submodule update --init --recursive
```

## 常用命令

构建 debug package：

```bash
./scripts/build.sh
```

运行单元测试并扫描 Stats 边界：

```bash
./scripts/test.sh
```

运行单个测试 target 或用例：

```bash
swift test --filter MacWatchCoreTests
swift test --filter TemperatureSchedulerTests/testName
```

运行 App：

```bash
./scripts/run.sh
```

打包 `.app`：

```bash
./scripts/package_app.sh
```

默认产物为 debug 构建；发布/资源验收使用：

```bash
./scripts/package_app.sh --configuration release
```

`package_app.sh` 会同时打包 SwiftPM 生成的本地化资源 bundle。它还支持 `--skip-build`、`--binary <path>` 和 `--output <bundle-path>`；复用自定义二进制时，二进制同级必须存在 `MacWatch_MacWatchApp.bundle`。

读取一次温度诊断 JSON Lines：

```bash
./scripts/probe_temperature_once.sh
```

运行阶段 7 验收：

```bash
./scripts/run_stage7_acceptance.sh
```

管理当前仓库的 OpenSpec（面向 Codex）：

```bash
./scripts/openspec.sh enable
./scripts/openspec.sh disable
./scripts/openspec.sh status
./scripts/openspec.sh update
```

说明：

- `enable` 会在仓库内安装或更新 OpenSpec CLI runtime，并为 Codex 生成当前仓库的 OpenSpec skills 和 slash command prompts。
- `disable` 会移除当前仓库注入到 Codex 的 OpenSpec skills 和 prompts，不会删除仓库内保存的 OpenSpec 配置与产物。
- `status` 用于查看当前仓库 OpenSpec 是否已安装、是否已启用，以及全局 prompt 挂载位置。
- `update` 会更新本地 OpenSpec runtime 到最新版本，并重新生成当前仓库的 OpenSpec 指令文件。

OpenSpec 精简使用指南：

- OpenSpec 适合先对齐“做什么、为什么、怎么做、分几步做”，再进入实现；不适合拿来替代所有日常小改动。
- 当前仓库启用的是 OpenSpec `core` 流程，常用能力只有 5 个：`explore`、`propose`、`apply`、`sync`、`archive`。
- 在 Codex 里通常直接使用 slash commands：`/opsx:explore`、`/opsx:propose`、`/opsx:apply`、`/opsx:sync`、`/opsx:archive`。

什么时候用什么：

- 需求还没想清楚，用 `/opsx:explore`
  例：想重新梳理 `system.temperature.hottest` 和 `sensor.temperature.raw` 的展示关系，但还没决定 UI 和状态文案怎么设计。
- 已经知道要做什么，但还没拆出方案和任务，用 `/opsx:propose <change-name>`
  例：`/opsx:propose add-ssd-trend-detail`，先生成 proposal、design 和 tasks，再评审是否进入实现。
- 方案和任务已经有了，要开始改代码，用 `/opsx:apply <change-name>`
  例：`/opsx:apply add-ssd-trend-detail`，按 tasks 逐项改 `Sources/MacWatchApp`、`Sources/MacWatchCore` 和对应测试。
- 变更里的规格增量要合回主 specs，但还不准备归档，用 `/opsx:sync <change-name>`
  例：把“菜单栏默认显示指标”的规格更新同步回 `openspec/specs/`，但实现还在继续。
- 这一轮需求已经完成，要正式收口，用 `/opsx:archive <change-name>`
  例：某次 Dashboard 温度详情改造已经完成实现、测试和规格同步后，归档该 change。

一句话判断：

- 不确定要不要做、怎么做：`explore`
- 确定要做，但还没形成正式变更：`propose`
- 正式开始写代码：`apply`
- 只想同步规格，不想结束 change：`sync`
- 这一轮做完了：`archive`

阶段 7 默认使用 release bundle 做资源验收；需要显式切换或指定摘要路径时可传入：

```bash
./scripts/run_stage7_acceptance.sh --configuration debug --summary-json dist/stage7-summary.json
```

验收摘要默认写入：

```text
dist/stage7-summary.json
```

分发预检依赖本机 Developer ID 证书和公证配置；缺少签名或公证凭据时，该项可能返回 `blocked`，不等同于温度主链路失败。需要指定身份或公证 profile 时可使用：

```bash
./scripts/preflight_distribution.sh --identity "Developer ID Application: Team" --notary-profile "profile-name" dist/MacWatch.app
```

验收 CLI 入口：

```bash
swift run MacWatchApp --probe-temperature-once
swift run MacWatchApp --acceptance-run probe-status
```

当前支持的 `--acceptance-run` 场景：`probe-status`、`dashboard-open`、`popup-open`、`trend-query`、`sleep-wake-simulated`、`first-run-guide`、`launch-main-window-on-start-enabled`、`launch-main-window-on-start-disabled`、`resources-steady-state`。

## MVP 边界

MVP 做：

- 本机温度采集、能力检测和状态展示。
- 菜单栏、Popup、Dashboard、兼容性页、详情趋势页、首次启动引导和基础设置。
- 本次 App 运行会话内的本地历史记录。
- 睡眠、唤醒、暂停、读取失败和数据过期造成的数据缺口处理。
- 默认本地隐私保护。

MVP 不做：

- CPU、GPU、内存、磁盘、电池功耗等非温度资源监控。
- 内存温度指标、进程统计、告警、导出、云同步、远程监控、Widget。
- 长期跨会话历史。
- 风扇控制、privileged helper 或任何 SMC 写操作。
- Stats `Reader` / `Module` 生命周期、`DB.shared`、LevelDB、Remote、Updater、通知或外部网络路径。

## 开发注意事项

- UI 只能访问 MacWatch 自己的 runtime、store、repository 和 settings，不能直接访问 IOKit、SMC、IOReport、DiskArbitration、SQLite、网络或 `Vendor/Stats`。
- 共享领域逻辑放入 `MacWatchCore`，系统采集适配放入 `StatsAdapter`，展示逻辑放入 `MacWatchApp`。
- `StatsAdapter` 不得写数据库、发通知、访问网络或持有 UI 状态。
- 内部温度统一使用摄氏度，UI 层按设置转换单位。
- 采集器失败不能导致 App 崩溃；单个指标失败不能影响其他指标。
- 睡眠、退出、暂停和连续读取失败不能补造数据，也不能在趋势图中跨缺口连线。
- 修改核心逻辑后至少运行 `./scripts/test.sh`；真实硬件温度无法验证时，用 fake probe、fixture 或 mock repository 验证领域逻辑，并说明未验证项。

## 主要文档

- `docs/origin/MacWatch_MVP版需求文档.md`
- `docs/origin/MacWatch_技术架构文档.md`
- `docs/origin/Stats_功能梳理_事实版.md`
- `docs/origin/Stats复用策略.md`
- `docs/architecture/stats-boundary.md`
- `docs/architecture/stats-temperature-source-audit.md`
