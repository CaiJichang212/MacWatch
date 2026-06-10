# AGENTS.md

本文件是 MacWatch 仓库的项目级 agent 指令。它只保留高优先级工作约束；产品细节、架构细节和验收细节以 `docs/origin` 中的文档为准。

## 语言

- 默认使用中文回答、说明计划和汇报结果。
- 代码标识、路径、命令、日志和系统 API 名称可以保留英文。
- 回答要直接、具体、可执行；不要用空泛描述代替判断。

## 工作前必读

涉及需求拆解、架构设计、开发计划或实现前，先查阅相关文档。为节省 token 和上下文窗口，优先阅读文档开头的索引目录，再按任务只检索和读取必要章节片段；不要默认把整篇文档塞入上下文：

- `docs/origin/MacWatch_MVP版需求文档.md`
- `docs/origin/MacWatch_技术架构文档.md`
- `docs/origin/Stats_功能梳理_事实版.md`
- `docs/origin/Stats复用策略.md`

不要在 `AGENTS.md` 中重复维护完整产品规格；如发现细节冲突，以用户最新明确指令和 `docs/origin` 文档为准，并说明取舍。

## 项目边界

MacWatch MVP 是本机温度监控工具，核心是 Apple Silicon MacBook Air 上的温度采集、能力检测、状态展示、会话历史和趋势查看。

MVP 不应擅自混入 Post-MVP 能力，包括但不限于：资源监控、进程统计、告警、导出、云同步、远程监控、Widget、风扇控制、长期跨会话历史。

优先用纵切方式推进：先打通 CPU 温度端到端链路，再横向补齐 GPU、内存、SSD/NAND、电池等温度状态。

## 目录职责

- `Sources/MacWatchApp`：macOS App 入口、菜单栏、窗口、Popup、设置和 SwiftUI 展示层。
- `Sources/MacWatchCore`：领域模型、采样调度、实时状态、会话历史、设置、趋势查询和核心业务逻辑。
- `Sources/StatsAdapter`：对 Stats 可复用只读采集逻辑的隔离适配层。
- `Vendor/Stats`：只读上游源码参考。
- `docs`：需求、架构、计划和开发说明。

不要修改无关目录。默认不要修改 `Vendor/Stats`；如确需核验或实验，先说明原因，并优先把结果沉淀到 MacWatch 自己的 adapter、patch 或文档中。

## Stats 复用硬边界

`Vendor/Stats` 不是稳定 SDK。MacWatch 只能通过 `StatsAdapter` 包装或移植必要的只读采集逻辑。

可以参考或迁移：

- HID Sensors、SMC 只读温度读取思路。
- Battery IORegistry 电池温度读取逻辑。
- NVMe SMART 内置 SSD/NAND 温度解析逻辑。
- 必要的 IORegistry、IOReport 读取片段。
- SystemKit 设备识别和 Apple Silicon 枚举思路。

禁止接入 MVP 默认链路：

- Stats `Reader` / `Module` 完整生命周期。
- Stats `DB.shared`、LevelDB 或短期历史策略。
- Stats `SystemStats`、Remote、MQTT、OAuth 或任何外部服务。
- Stats Updater、外部 IP 查询、联网检查。
- Stats 通知、Widget、LaunchAtLogin helper。
- SMC privileged helper、风扇控制、SMC 写操作。

`StatsAdapter` 不得写数据库、发通知、访问网络或持有 UI 状态。

## 实现原则

- UI 只能访问 MacWatch 自己的 store、repository 和 settings，不直接访问 IOKit、SMC、IOReport、DiskArbitration、SQLite、网络或 `Vendor/Stats`。
- 不可读取的温度指标必须展示明确状态，例如 `unsupported`、`readFailed` 或 `stale`；不能显示为 `0°C`、空白、旧值或估算值。
- 采集器失败不能导致 App 崩溃；单个指标失败不能影响其他指标。
- 内部温度值统一使用摄氏度，UI 层按设置转换单位。
- 睡眠、退出、暂停、连续读取失败等数据缺口不能补造，也不能在趋势图中跨缺口连线。
- 默认不联网、不上传、不记录用户文件名、网络内容、窗口标题或进程列表。
- 不引入 privileged helper，不做风扇控制或任何 SMC 写操作。

## 工程质量

- 保持文件职责单一；不要把 App 入口、视图、模型、采集、存储和格式化逻辑塞进一个大文件。
- 共享领域逻辑放入 `MacWatchCore`，系统采集适配放入 `StatsAdapter`，展示逻辑放入 `MacWatchApp`。
- 修改核心逻辑时补充测试或给出可复现验证步骤。
- 如当前环境无法验证真实硬件温度，使用 fake probe、fixture 或 mock repository 验证领域逻辑，并明确说明未验证项。
- 性能和能耗敏感路径避免高频传感器枚举、SMART 高频读取和主线程阻塞。

## Git 与协作

- 不回滚用户未要求回滚的改动。
- 不修改无关文件。
- 手工编辑保持改动小而清晰。
- 生成计划、设计或阶段文档时，优先放入 `docs` 下合适目录。
- 涉及提交、分支或 PR 时，先检查当前工作区状态，再按用户要求执行。
