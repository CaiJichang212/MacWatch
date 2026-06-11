# MacWatch

MacWatch 是一个面向 Apple Silicon MacBook Air 的本机温度监控工具。当前 MVP 聚焦温度主链路：采集 CPU、GPU、内存、内置 SSD/NAND、电池以及系统/传感器温度中可读取的指标，展示实时状态，记录本次运行会话历史，并提供趋势查看。

项目默认本地运行，不联网、不上传，不记录用户文件名、网络内容、窗口标题或进程列表。Stats 只作为只读上游参考，MacWatch 通过自己的 `StatsAdapter` 隔离必要的只读采集逻辑。

## 当前状态

当前源码已包含 MVP 主链路与阶段 7 验收收口相关能力：

- Swift Package 工程，目标平台为 macOS 13 及以上。
- `MacWatchApp`：SwiftUI App、菜单栏入口、Popup、Dashboard、兼容性页、温度详情页、设置页、首次启动引导和验收 CLI。
- `MacWatchCore`：温度领域模型、能力检测、采样调度、实时状态、设置、本次运行会话历史、SQLite 存储、趋势查询和降采样。
- `StatsAdapter`：CPU、GPU、内存、SSD/NAND、电池、系统温度和传感器温度 probe；只读 HID、SMC、IORegistry、NVMe SMART 等适配代码。
- `StatsAdapterIOHID`：最小 Objective-C HID 只读桥接 target。
- `Tests`：Core、App、StatsAdapter 单元测试，以及 Stats 边界和阶段 7 验收脚本相关测试。
- `scripts/run_stage7_acceptance.sh`：阶段 7 验收入口，覆盖 probe 状态、Dashboard/Popup、首次启动、趋势查询、睡眠唤醒模拟、资源、网络、Stats 边界和分发预检。

硬件实测能力取决于运行机器和 macOS 暴露的系统接口。不可读指标必须显示为 `unsupported`、`readFailed` 或 `stale`，不能显示为 `0°C`、空白、旧值或估算值。

## 项目结构

```text
MacWatch/
  Package.swift
  Sources/
    MacWatchApp/          # App 入口、菜单栏、窗口、Popup、设置和 SwiftUI 展示层
    MacWatchCore/         # 领域模型、采样调度、实时状态、会话历史和核心业务逻辑
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

初始化 submodule：

```bash
git submodule update --init --recursive
```

## 常用命令

构建：

```bash
./scripts/build.sh
```

运行单元测试并扫描 Stats 边界：

```bash
./scripts/test.sh
```

运行 App：

```bash
./scripts/run.sh
```

打包调试版 `.app`：

```bash
./scripts/package_app.sh
```

读取一次温度诊断 JSON Lines：

```bash
./scripts/probe_temperature_once.sh
```

运行阶段 7 验收：

```bash
./scripts/run_stage7_acceptance.sh
```

验收摘要默认写入：

```text
dist/stage7-summary.json
```

分发预检依赖本机 Developer ID 证书和公证配置；缺少签名或公证凭据时，该项可能返回 `blocked`，不等同于温度主链路失败。

## MVP 边界

MVP 做：

- 本机温度采集、能力检测和状态展示。
- 菜单栏、Popup、Dashboard、兼容性页、详情趋势页和基础设置。
- 本次 App 运行会话内的本地历史记录。
- 睡眠、唤醒、暂停、读取失败和数据过期造成的数据缺口处理。
- 默认本地隐私保护。

MVP 不做：

- CPU、GPU、内存、磁盘、电池功耗等非温度资源监控。
- 进程统计、告警、导出、云同步、远程监控、Widget。
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
