# MacWatch 开发复盘与可复用工程经验

更新日期：2026-07-03

适用范围：MacWatch 后续需求、实现、测试、打包与发布验收。

## 索引目录（大模型检索用）

> 使用方式：先按本索引定位需要章节，再只读取对应标题下的片段，避免把整篇文档塞入上下文。

- [1. 核心结论](#1-核心结论)：开发原则与推荐流程。
- [2. 高频问题与解决方式](#2-高频问题与解决方式)：常见后果、根因与处理方法速查。
- [3. 已验证的典型故障](#3-已验证的典型故障)
  - [3.1 阶段 7 CPU 误判](#31-阶段-7-cpu-误判已解决)
  - [3.2 SwiftPM 本地化资源未进入 `.app`](#32-swiftpm-本地化资源未进入-app-p0未解决)
  - [3.3 分发预检阻塞](#33-分发预检阻塞外部条件)
- [4. 可复用设计约束](#4-可复用设计约束)
  - [4.1 温度状态](#41-温度状态)
  - [4.2 本地化与设置](#42-本地化与设置)
  - [4.3 AppKit 命令](#43-appkit-命令)
  - [4.4 硬件读取](#44-硬件读取)
- [5. 精简验证流程](#5-精简验证流程)
  - [5.1 内循环](#51-内循环)
  - [5.2 仓库门禁](#52-仓库门禁)
  - [5.3 按风险追加验证](#53-按风险追加验证)
- [6. 可删除的重复步骤](#6-可删除的重复步骤)：可安全合并或省略的验证步骤。
- [7. Definition of Done](#7-definition-of-done)：变更完成检查清单。
- [8. 当前待处理项](#8-当前待处理项)：尚未解决的风险与技术债。

## 1. 核心结论

后续开发优先遵守以下原则：

1. **先锁定产品边界，再改代码。** 用户最新明确要求高于旧需求文档；发生冲突时应同步规格，避免旧规则再次引发返工。
2. **正常信息精简，异常信息完整。** 概览只展示设备名、当前温度和必要的平均温度；`unsupported`、`readFailed`、`stale` 才展示状态和原因；来源、采样与诊断信息留在详情页。
3. **跨层概念只有一个权威映射。** domain、metric、source、详情可选项不得在多个模块分别推断。
4. **测试通过不等于产物可发布。** SwiftPM 测试、真实硬件读取、独立 `.app` 和发布预检覆盖不同风险，不能互相替代。
5. **每条验证都应提供新证据。** 内循环跑定向测试，提交前跑仓库门禁，涉及 UI/资源/窗口时验证独立 `.app`，发布前再跑完整阶段验收。

推荐流程：

```text
需求与边界确认
  → 最小失败复现
  → 定向测试与实现
  → ./scripts/test.sh
  → 独立 .app / 真实硬件验证（按风险）
  → release 阶段验收（发布前）
```

## 2. 高频问题与解决方式

| 问题模式 | 典型后果 | 解决方式 |
| --- | --- | --- |
| 产品边界确认过晚 | memory temperature 等越界能力进入 Core、采集、UI、测试和文档后再整链路删除 | 实现前列出允许与禁止能力；新增或删除 domain 时核对 Core、Adapter、App、Settings、History、CLI、Tests、Docs |
| domain/metric/source 分散映射 | 详情页跨域选择、传感器分类错误、来源错误 | Core 保留稳定标识；StatsAdapter 负责 raw key 映射；App catalog 只负责标题、排序和可见指标；增加集合相等与跨域测试 |
| 正常与异常信息层级不清 | Popup/Dashboard 重复显示 `Valid`、Source、逐卡时间和 `ok` | 在 presentation model 统一“正常静默、异常明确”，两个视图只消费结果，不各写一套条件 |
| 设置模型无迁移设计 | 新增语言字段后旧 JSON 解码失败并重置全部设置 | 新字段提供兼容默认值；未知语言回退 `.system`；迁移测试同时断言旧字段保持不变 |
| 本地化只覆盖 SwiftUI | 菜单、窗口标题或状态栏切换语言后不刷新 | SwiftUI、普通字符串和 AppKit 共用一个 localizer；由 AppDelegate 集中分发 settings change |
| 单一设置回调被重复赋值 | 后注册者覆盖前注册者，部分界面保持旧语言 | 只在一个入口注册 `settingsDidChange`；消费者增多时改为观察者集合、通知或 `AsyncStream` |
| AppKit 全局状态未隔离 | 菜单/窗口测试顺序依赖或偶发失败 | 测试前保存并清空 `NSApp.mainMenu/windowsMenu`，结束后恢复并关闭测试窗口 |
| 性能指标口径不明确 | CPU 实际合格却被阶段验收判失败 | 报告同时保存原始值、归一化因子和派生值；固定工具、单位、分母、配置、采样时长和阈值 |
| `failed`、`blocked`、warning 混淆 | 缺少证书被误当成业务回归，或警告长期无人处理 | `failed` 表示实现/产物不合格；`blocked` 表示外部条件缺失；warning 单独进入技术债 |
| 构建目录回退掩盖产物缺失 | 本机运行正常，独立 `.app` 在其他机器启动失败 | 检查 app 内资源，隔离 `.build` 后启动产物，禁止用 `swift run` 代替打包验证 |
| 任务勾选缺少证据 | OpenSpec 显示完成，但产物并不满足要求 | 每个任务关联测试名、命令、产物路径或截图清单后再勾选 |

## 3. 已验证的典型故障

### 3.1 阶段 7 CPU 误判（已解决）

`ps -o pcpu` 的原始进程 CPU 百分比曾被直接与整机 `< 2%` 阈值比较。现已按 `hw.logicalcpu` 归一化，并在报告中同时保留：

- `rawAverageCpuPercent`
- `cpuNormalizationFactor`
- `averageCpuPercent`

可复用经验：性能修复必须先用固定 mock 样本锁定公式，再运行真实 release 测量；不能只断言最终 `passed`。

### 3.2 SwiftPM 本地化资源未进入 `.app`（P0，未解决）

当前 `Package.swift` 已声明本地化资源，但 `package_app.sh` 只复制可执行文件和 `Info.plist`。`Bundle.module` 在开发机上可回退到 `.build/.../MacWatch_MacWatchApp.bundle`，因此测试可能通过；离开源码树后资源不可用并可能触发 `fatalError`。

完成标准：

- 将 `MacWatch_MacWatchApp.bundle` 复制到生成 accessor 查找的位置。
- 打包测试断言英文和 `zh-Hans` 资源存在。
- 临时隔离 `.build` 后，`dist/MacWatch.app` 仍可启动。
- 验证“跟随系统 / 中文 / English”即时切换。

### 3.3 分发预检阻塞（外部条件）

`missingDeveloperIDIdentity` 表示本机缺少 Developer ID 身份，不属于温度业务失败。开发阶段保留为 `blocked`；正式发布前必须在具备证书和公证凭据的环境解决。

## 4. 可复用设计约束

### 4.1 温度状态

- `valid` 必须携带合法温度。
- `unsupported`、`readFailed`、`stale` 不得参与 hottest 计算，也不得显示为 `0°C` 或伪装成当前值。
- CPU/GPU 有有效 hottest 时可保留 average。
- 概览可隐藏正常状态文字，但不能删除领域状态。
- 单个 probe 失败不能阻塞其他 domain。

### 4.2 本地化与设置

- 语言默认 `.system`，不要保存当前系统语言快照。
- 用户文本进入 `Localizable.strings`；中英文 key 集合保持一致。
- domain raw value、metric name、JSON key、CLI 参数、日志和验收场景名保持稳定英文标识。
- 格式化文本使用占位符，不拼接英文前缀。
- 语言变化必须刷新 Popup、状态栏、窗口标题和主菜单，无需重启。

### 4.3 AppKit 命令

- 快捷键只在主菜单集中注册：`⌘W`、`⌘,`、`⌘Q`。
- `⌘W` 使用 responder chain 的 `performClose:`，只关闭当前窗口。
- `⌘,` 打开或聚焦单例设置窗口。
- `⌘Q` 使用标准 terminate 生命周期，确保会话和历史正确收尾。
- 测试枚举全部 key equivalent，既检查遗漏，也防止意外新增快捷键。

### 4.4 硬件读取

- fake/fixture 验证确定性逻辑；真实 Mac 验证系统接口、raw key 和机型兼容性。
- 真实机器读不到时返回明确不可用状态，不使用估算值或旧值替代。
- 不修改 `Vendor/Stats`；只在 `StatsAdapter` 添加只读适配。
- 性能报告记录配置、工具、原始值、归一化口径、采样参数和机器信息。

## 5. 精简验证流程

### 5.1 内循环

| 改动类型 | 首选验证 |
| --- | --- |
| Core 设置、模型、历史、调度 | 对应 `MacWatchCoreTests` filter |
| StatsAdapter、catalog、probe | 对应 `StatsAdapterTests` filter；边界变化时再跑 boundary script |
| 展示模型、本地化、UI 状态 | 对应 `MacWatchAppTests` filter |
| AppDelegate、窗口、菜单、快捷键 | App 测试 + 一次真实 `.app` smoke test |
| 脚本 | 对应 ScriptTests，使用固定 mock 输入 |
| 真实采集 | fake probe 通过后再运行一次真实 probe |

### 5.2 仓库门禁

功能完成后只需运行：

```bash
./scripts/test.sh
```

该脚本已经包含全量 `swift test` 和 Stats 边界检查，之后不要重复手工执行相同子命令。

### 5.3 按风险追加验证

- UI、菜单、窗口、资源或启动行为：打包并从 `.app` 验证。
- 采集与兼容性：fake 路径通过后验证目标硬件。
- 资源、网络、睡眠唤醒或发布逻辑：运行相关阶段 7 场景。
- 发布前：运行完整 release 阶段验收。

以下验证不能互相替代：单元测试与独立 `.app`、fake probe 与真实硬件、debug 与 release、静态边界扫描与运行时网络检查、Codable fixture 与真实升级数据。

## 6. 可删除的重复步骤

- `swift test` 后通常无需再执行相同配置的 `swift build`。
- `./scripts/test.sh` 后无需再手工运行 `swift test` 或 `verify_stats_boundary.sh`。
- 完整阶段 7 会自行 release 打包，通常无需提前单独运行 `package_app.sh`。
- 小型 UI 文案修改先跑展示层测试，不必每次运行完整阶段 7。
- OpenSpec 的 proposal、spec、design、tasks 各保留自身职责；tasks 只引用 requirement、实现切片和验证证据，不重复抄写规格全文。
- Stage 7 普通场景应改为数据驱动循环；mock 与真实资源采样应共用同一 parser/聚合逻辑。

精简原则：删除不增加新证据的重复命令，不删除覆盖不同风险的验证层。

## 7. Definition of Done

- [ ] 用户最新要求与 origin/OpenSpec 无未说明冲突。
- [ ] 未引入非温度资源监控、内存温度、联网、helper 或风扇控制等越界能力。
- [ ] 相关定向测试通过。
- [ ] `./scripts/test.sh` 通过。
- [ ] UI、资源、菜单、窗口或启动变更已验证独立 `.app`，且不依赖 `.build`。
- [ ] 采集变更已验证 fake 路径；有目标硬件时完成真实 probe，否则记录未验证条件。
- [ ] 发布相关变更已运行所需阶段验收。
- [ ] `failed` 已清零；`blocked` 和 warning 有明确后续处理。
- [ ] OpenSpec 任务有测试、命令、产物或截图证据。
- [ ] `git diff --check` 通过，工作区没有无关改动或意外生成物。

## 8. 当前待处理项

1. **P0：** 修复 `.app` 未打包 `MacWatch_MacWatchApp.bundle`，增加独立产物资源测试。
2. **P1：** 补充 `NSApp.mainMenu` 已存在时的菜单安装测试；当前实现仅在菜单为 `nil` 时创建命令。
3. **P1：** 消除 `@Sendable` 默认闭包警告，并增加严格并发构建检查。
4. **P1：** 将 Stage 7 普通场景改为数据驱动循环，增加定向场景与明确退出码。
5. **P1：** 归档 OpenSpec 前同步最新 UI、双语与快捷键规则，确保规格和产物一致。
6. **P2：** 明确 `dist/stage7-summary.json` 是版本化证据还是可忽略的运行产物。
7. **发布条件：** 正式分发前配置 Developer ID Application 和公证凭据。
