# Stats_功能梳理 源码核验报告

核验对象：
- 原文：[Stats_功能梳理.md](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/docs/origin/Stats_功能梳理.md)
- 源码目录：`/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats`

核验目的：
- 识别原文中哪些描述与源码一致
- 识别哪些描述只有部分源码依据、但表述过强
- 识别哪些描述在源码中缺少直接依据
- 识别哪些内容本质上是面向 MacWatch 的建议，而不是 Stats 现状事实

状态标记说明：
- `属实`：源码中能直接找到充分依据
- `部分属实 / 表述过强`：源码有一定依据，但原文概括超出了源码证据
- `无源码依据`：在本次核验范围内未找到直接支持
- `属于建议，不是源码事实`：这是对 MacWatch 的判断或设计建议，不应当写成 Stats 现状

---

## 重点问题汇总

### 1. `Reader` 是否同时负责 UI / DB / 远程？

- 结论：`部分属实 / 表述过强`
- 说明：
  - `Reader.callback(_:)` 确实会调用外部 callback、`SystemStats.shared.send(...)` 和 `DB.shared.insert(...)`，说明 Reader 基类直接参与 UI 回调、远程发送和 DB 写入。[reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:113) [reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:118)
  - 但“发送给 UI”并不是 Reader 直接操作 UI，而是通过各模块在初始化 Reader 时传入的 callback 间接更新 popup/widget/settings。[Modules/CPU/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/CPU/main.swift:147) [Modules/Net/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/main.swift:187)
- 修正建议：
  - 将原文中的“Reader 通过 callback 将采集结果发送给 UI、通知、远程服务和短期 DB”改成“Reader 基类负责触发模块 callback、远程发送和 DB 写入；UI 更新通常发生在模块传入的 callback 中”。

### 2. `DB` 的 TTL、写入节流、用途边界

- 结论：`部分属实 / 表述过强`
- 说明：
  - TTL 1 小时有直接证据：`private let ttl: Int = 60*60`。[DB.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/DB.swift:19)
  - 普通键值写入有 30 秒节流：`< 30`。[DB.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/DB.swift:85)
  - Reader 侧是否写历史还取决于 `history` 标志，以及 `interval * 10` 的节奏控制。[reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:119)
  - 但“它更适合作为菜单栏图表缓存”属于推论，不是源码显式声明。
- 修正建议：
  - 保留 TTL 与节流描述。
  - 删除或降级“更适合作为菜单栏图表缓存”这类用途判断，标记为“基于实现的推断”。

### 3. `Module` 生命周期与 Reader 启停机制

- 结论：`属实`
- 说明：
  - `mount()`/`enable()` 会初始化 store interval 并 `reader.start()`。[module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:177)
  - `disable()` 会 `reader.stop()` 并关闭菜单栏项。[module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:223)
  - popup 可见性会影响 `popup || sleep` 类型 reader 的 `unlock/start` 与 `pause/lock`。[module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:261)
  - 预览窗口可见性会影响 `preview || sleep` 类型 reader。[module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:273)
- 修正建议：
  - 原文这部分基本成立，但“根据设置页可见性动态启动或暂停相关 Reader”应改成“根据 popup 和 preview/window 打开状态影响部分 reader”，因为不是所有 setting tab 可见性都会直接触发。

### 4. 各模块默认开启/关闭状态

- 结论：`属实`
- 说明：
  - 默认状态来自各模块 `config.plist` 的 `State` 字段，并在 `Module` 初始化时读入 `enabled`。[module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:130)
  - 当前源码中：
    - 默认开启：CPU、RAM、Disk、Net、Battery
    - 默认关闭：Sensors、GPU、Bluetooth、Clock、Remote
  - 依据：各模块 `config.plist` 的 `State`。[CPU/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/CPU/config.plist:1) [Net/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/config.plist:1) [Remote/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Remote/config.plist:1)
- 修正建议：
  - 原文默认状态判断可保留。

### 5. Network / GPU / Sensors / Bluetooth / Remote 是否被夸大

- 结论：
  - Network：`部分属实 / 表述过强`
  - GPU：`部分属实 / 表述过强`
  - Sensors：`部分属实 / 表述过强`
  - Bluetooth：`部分属实 / 表述过强`
  - Remote：`部分属实 / 表述过强`
- 说明：
  - Network 确实有 `UsageReader`、`ProcessReader`、`ConnectivityReader`，但“ICMP 或 HTTP HEAD”是原文概括，需要以源码实际模式为准；公网 IP 是直接 `curl https://api.mac-stats.com/ip`。[Net/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/main.swift:195) [Net/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/readers.swift:494)
  - GPU 确实读取 utilization / renderer / tiler / 温度 / 风扇 / 时钟 / ANE / FPS，但不同项依赖平台与驱动统计，原文写法过于像“所有 GPU 都稳定提供全部字段”。[GPU/reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/GPU/reader.swift:139)
  - Sensors 确实有 SMC、HID、IOReport、派生传感器和阈值通知，但“对 MacWatch 价值最高”属于主观判断，不是源码事实。[Sensors/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Sensors/readers.swift:272)
  - Bluetooth 确实混合使用 CoreBluetooth、IOBluetooth、`system_profiler`、`pmset -g accps -xml`，但“提供连接状态、RSSI、电量等能力”应注明以可探测设备为限。[Bluetooth/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Bluetooth/readers.swift:67) [Bluetooth/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Bluetooth/readers.swift:276)
  - Remote 不是简单“外部远程监控/控制”一句话能概括；当前源码包含完整的 `system-stats.com` 云端接入、OAuth、MQTT、设备注册、远程机器与主机列表读取。[SystemStats.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/SystemStats.swift:29) [Remote/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Remote/main.swift:1)
- 修正建议：
  - 这些模块都应增加“字段与能力受平台/权限/设备类型约束”的说明。

### 6. 风扇控制、远程监控、公网 IP、更新检查等网络/权限相关能力

- 结论：`属实`
- 说明：
  - 风扇控制：存在 `SMC` CLI、helper、`setFanMode`、`setFanSpeed`、`resetFanControl`，并在 Sensors popup 中暴露安装 helper 与调速 UI。[SMC/Helper/protocol.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/SMC/Helper/protocol.swift:18) [Sensors/popup.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Sensors/popup.swift:603)
  - 远程监控：`SystemStats` 直接配置了 `api.system-stats.com`、`oauth.system-stats.com`、`broker.system-stats.com`、`app.system-stats.com`。[SystemStats.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/SystemStats.swift:29)
  - 公网 IP：Network 模块直接调用 `curl -s -4/-6 https://api.mac-stats.com/ip`。[Net/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/readers.swift:494)
  - 更新检查：AppDelegate 初始化了 `Updater(github:url:)`，URL 指向 `https://api.mac-stats.com/release/latest`。[AppDelegate.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/AppDelegate.swift:25)
- 修正建议：
  - 原文可以更明确地点出“源码中确有外部联网能力”，不要只写成抽象风险提示。

### 7. “Stats 对 MacWatch 的启示”哪些是建议，哪些是事实

- 结论：`大量内容属于建议，不是源码事实`
- 说明：
  - 从“MacWatch 可复用点”“需要增强点”“MVP 建议”“主存储改为 SQLite/GRDB”“默认本地化、隐私优先”等开始，内容已经明显转入产品和架构建议。
- 修正建议：
  - 整个第 6-8 节建议统一加前缀“面向 MacWatch 的推论/建议”，不要与前文源码核验混写。

---

## 分章节核验

## 1. 项目概述

### 1.1 第 10 行

- 原文位置：`Stats_功能梳理.md:10`
- 原始表述摘要：Stats 是菜单栏系统监控工具，覆盖 CPU/GPU/内存/磁盘/网络/电池/传感器/蓝牙/时钟/远程监控，并提供 widget、popup、通知、设置、macOS Widget、远程监控和部分风扇控制。
- 核验结论：`属实`
- 源码依据：
  - 模块入口包含 `CPU/RAM/Disk/Net/Battery/Sensors/GPU/Bluetooth/Clock/Remote`。[AppDelegate.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/AppDelegate.swift:11) [AppDelegate.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/AppDelegate.swift:26)
  - `Widgets/` 目录存在桌面 Widget 扩展。
  - 风扇控制相关 helper 和 UI 存在。[SMC/Helper/protocol.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/SMC/Helper/protocol.swift:18) [Sensors/popup.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Sensors/popup.swift:603)
- 修正建议：
  - 可补一句“远程与风扇控制属于额外能力，不是所有机器都等价可用”。

### 1.2 第 12 行

- 原文位置：`Stats_功能梳理.md:12`
- 原始表述摘要：LevelDB 历史能力偏短期缓存，不适合作为长期趋势记录主存储。
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - DB 历史 TTL 为 1 小时。[DB.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/DB.swift:19)
  - 历史键会在 `clean(_:)` 中清理过期项。[DB.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/DB.swift:95)
- 修正建议：
  - “不适合作为长期趋势记录主存储”应改成“从当前 TTL 与写入策略看，更偏向短期缓存实现，这是对长期趋势场景的不利因素”。

## 2. 源码结构概览

### 2.1 第 20-25 行

- 原文位置：`Stats_功能梳理.md:20-25`
- 原始表述摘要：`Stats/`、`Kit/`、`Modules/`、`SMC/`、`Widgets/`、`LaunchAtLogin/` 的目录作用。
- 核验结论：`属实`
- 源码依据：
  - 目录实际存在，且对应源码内容与描述基本一致。
  - `LaunchAtLogin/main.swift`、`Widgets/UnitedWidget.swift`、`Stats/AppDelegate.swift`、`Kit/module/module.swift`、`SMC/main.swift` 等均可对应。
- 修正建议：
  - 无需大改。

## 3. 全局架构

### 3.1 第 29 行

- 原文位置：`Stats_功能梳理.md:29`
- 原始表述摘要：Stats 使用“模块化 + 采集器 + 菜单栏组件”架构。
- 核验结论：`属实`
- 源码依据：
  - App 维护全局 `modules: [Module]`。[AppDelegate.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/AppDelegate.swift:26)
  - `Module` 负责 reader、menuBar、popup、window、settings 组合。[module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:111)
- 修正建议：
  - 无需大改。

### 3.2 第 53-58 行，AppDelegate 职责

- 原文位置：`Stats_功能梳理.md:53-58`
- 原始表述摘要：初始化模块、启动 `mount()`、终止 `terminate()`、管理窗口、通知动作、全局快捷键、暂停监控、远程登录状态、自动更新检查、崩溃后状态恢复。
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - 初始化模块、`mount()`、`terminate()`、设置/更新/支持/Setup 窗口、通知代理、远程状态监听、更新检查都能找到依据。[AppDelegate.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/AppDelegate.swift:26) [AppDelegate.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/AppDelegate.swift:77) [AppDelegate.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/AppDelegate.swift:99)
  - `NSEvent.addGlobalMonitorForEvents` 与 `addLocalMonitorForEvents` 支持全局/本地按键处理。[AppDelegate.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/AppDelegate.swift:87)
  - 但“崩溃后状态恢复”在本次核验中没有看到明确实现。
- 修正建议：
  - 删除“崩溃后状态恢复”，或标记为“未在当前抽查源码中确认”。

### 3.3 第 64-68 行，Module 基类能力

- 原文位置：`Stats_功能梳理.md:64-68`
- 原始表述摘要：读取 config、维护状态、生命周期、根据 Popup/设置页/Preview 启停 Reader、响应全局通知。
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - 读取 config、状态、生命周期、通知监听都有直接依据。[module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:121) [module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:146)
  - Reader 启停与 popup/preview 可见性有关，但“设置页可见性”这一说法过泛。[module.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/module.swift:261)
- 修正建议：
  - 改成“根据 popup 和 preview/window 状态影响部分 reader 的暂停与唤醒”。

### 3.4 第 76-81 行，Reader 基类能力

- 原文位置：`Stats_功能梳理.md:76-81`
- 原始表述摘要：维护采集间隔、历史写入间隔、Popup/Preview/Sleep 状态；使用 Repeater；callback 发往 UI/通知/远程/DB；读取刷新间隔；支持生命周期与秒边界对齐。
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - interval、popup、preview、sleep、Repeater、`start/pause/stop/setInterval/sleepMode`、秒边界对齐都有直接实现。[reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:85) [reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:171) [reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:211)
  - “历史写入间隔”不是独立字段，而是 `lastDBWrite` 配合 `interval * 10` 的逻辑。[reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:119)
  - “通知”不是 Reader 基类统一能力，而是通常由模块 callback 再转给 notifications view。
- 修正建议：
  - 将“通知”从 Reader 基类职责中移除，或改为“Reader 输出会被模块层用于驱动 UI/通知”。

### 3.5 第 87-102 行，Widget 类型

- 原文位置：`Stats_功能梳理.md:87-102`
- 原始表述摘要：列出 widget 类型 `mini / line_chart / bar_chart / pie_chart / network_chart / speed / battery / battery_details / sensors / memory / label / tachometer / state / text`
- 核验结论：`属实`
- 源码依据：
  - `widget_t` 枚举直接定义这些类型，其中 `sensors` 对应 case 名为 `stack`，rawValue 为 `"sensors"`。[widget.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/widget.swift:16)
- 修正建议：
  - 建议在文档里注明：源码内部 case 名是 `stack`，显示值是 `sensors`，避免后续搜索不到。

### 3.6 第 108-116 行，Store 与 DB

- 原文位置：`Stats_功能梳理.md:108-116`
- 原始表述摘要：Store 是 UserDefaults 封装；DB 使用 LevelDB，存储最新值和短期历史，TTL 约 1 小时，并有最小写入间隔限制。
- 核验结论：`属实`
- 源码依据：
  - Store 维护缓存与 UserDefaults 持久化。[Store.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/Store.swift:14)
  - DB TTL 1 小时、30 秒节流、latest key + timestamped history key 明确存在。[DB.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/DB.swift:19) [DB.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/DB.swift:77)
- 修正建议：
  - 可补充“底层是 LLDB 封装，不是直接暴露 LevelDB API”。

### 3.7 第 120-127 行，SystemKit

- 原文位置：`Stats_功能梳理.md:120-127`
- 原始表述摘要：SystemKit 识别 CPU 架构、机型、序列号、启动时间、系统版本、CPU/GPU/RAM/磁盘/显示器、核心类型。
- 核验结论：`属实`
- 源码依据：
  - `Platform` 包含 Intel 与 M1-M5 各代/Pro/Max/Ultra。[SystemKit.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/SystemKit.swift:14)
  - `device_s`、`info_s`、`cpu_s/gpu_s/disk_s/display_s` 等结构与初始化逻辑支持上述信息。[SystemKit.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/SystemKit.swift:178)
- 修正建议：
  - 可保留。

### 3.8 第 131-137 行，SMC 与 Helper

- 原文位置：`Stats_功能梳理.md:131-137`
- 原始表述摘要：SMC 目录提供 SMC CLI 和 privileged helper，可枚举 key、读取硬件值、读取风扇信息、设置风扇模式/转速、重置风扇控制。
- 核验结论：`属实`
- 源码依据：
  - CLI 与 Helper 目录存在。
  - `setFanMode`、`setFanSpeed`、`resetFanControl` 在 helper 协议与实现中都存在。[SMC/Helper/protocol.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/SMC/Helper/protocol.swift:18) [SMC/Helper/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/SMC/Helper/main.swift:118)
- 修正建议：
  - 可保留。

## 4. 模块功能梳理

### 4.1 CPU 模块

- 原文位置：`Stats_功能梳理.md:147-167`
- 核验结论：`属实`
- 源码依据：
  - 默认开启：`State = 1`。[CPU/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/CPU/config.plist:1)
  - Reader 组合：`LoadReader`、`ProcessReader`、`AverageLoadReader`、`TemperatureReader`、`LimitReader`、`FrequencyReader`。[CPU/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/CPU/main.swift:147)
  - `TemperatureReader` 使用多个 SMC key。[CPU/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/CPU/readers.swift:260)
  - `FrequencyReader` 使用 IOReport。[CPU/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/CPU/readers.swift:312)
  - `LimitReader` 使用 `pmset`。[CPU/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/CPU/readers.swift:542)
  - `AverageLoadReader` 使用 `uptime`。[CPU/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/CPU/readers.swift:586)
- 修正建议：
  - “Apple Silicon 上区分 E-Core、P-Core、S-Core”可以保留，但建议加上“取决于 `SystemKit` 与 IOReport 可用信息”。

### 4.2 RAM 模块

- 原文位置：`Stats_功能梳理.md:173-192`
- 核验结论：`属实`
- 源码依据：
  - 默认开启：`State = 1`。[RAM/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/RAM/config.plist:1)
  - `UsageReader` 用 `host_info`、`host_statistics64`、`sysctlbyname("vm.swapusage")` 与 `kern.memorystatus_vm_pressure_level`。[RAM/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/RAM/readers.swift:15)
  - `ProcessReader` 用 `top -l 1 -o mem`。[RAM/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/RAM/readers.swift:122)
- 修正建议：
  - 可保留。

### 4.3 Disk 模块

- 原文位置：`Stats_功能梳理.md:198-215`
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - 默认开启：`State = 1`。[Disk/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Disk/config.plist:1)
  - `CapacityReader` 使用 `FileManager`、`DiskArbitration`、`statfs`、IORegistry、NVMe SMART。[Disk/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Disk/readers.swift:36)
  - `ActivityReader` 使用 IORegistry `Statistics` 差分。[Disk/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Disk/readers.swift:247)
  - `ProcessReader` 确实存在，但原文写“`ps + proc_pid_rusage`”需要以实现细节为准，不宜在未逐行复核时写死。
- 修正建议：
  - Reader 数据来源建议改成“以进程 API/系统命令获取磁盘活跃进程”，除非后续逐行确认实现细节。

### 4.4 Network 模块

- 原文位置：`Stats_功能梳理.md:221-240`
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - 默认开启：`State = 1`。[Net/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/config.plist:1)
  - Reader 组合确实有 `UsageReader`、`ProcessReader`、`ConnectivityReader`。[Net/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/main.swift:144)
  - `UsageReader` 读取接口、IP、DNS、Wi‑Fi、Reachability、公网 IP。[Net/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/readers.swift:101) [Net/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/readers.swift:494)
  - `ProcessReader` 使用 `nettop`。[Net/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Net/readers.swift:601)
  - 文中“ICMP 或 HTTP HEAD”未直接对应为源码字面描述，属于概括。
- 修正建议：
  - 明确公网 IP 是外部 API。
  - 将连通性检测写成“存在 `ConnectivityReader`，具体模式由设置控制”，不要先验写成固定实现。

### 4.5 Battery 模块

- 原文位置：`Stats_功能梳理.md:246-265`
- 核验结论：`属实`
- 源码依据：
  - 默认开启：`State = 1`。[Battery/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Battery/config.plist:1)
  - `UsageReader` 使用 `IOPSCopyPowerSourcesInfo`、`AppleSmartBattery`、外部电源适配器、`ChargerData`。[Battery/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Battery/readers.swift:61) [Battery/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Battery/readers.swift:106)
  - `ProcessReader` 使用 `top -o power`。[Battery/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Battery/readers.swift:169)
- 修正建议：
  - 可保留。

### 4.6 Sensors 模块

- 原文位置：`Stats_功能梳理.md:271-300`
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - 默认关闭：`State = 0`。[Sensors/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Sensors/config.plist:1)
  - SMC/HID/IOReport、风扇、派生传感器、阈值通知都能找到直接实现。[Sensors/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Sensors/readers.swift:46) [Sensors/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Sensors/readers.swift:422) [Sensors/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Sensors/readers.swift:495) [Sensors/notifications.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Sensors/notifications.swift:80)
  - “对 MacWatch 价值最高”是主观产品判断，不是源码事实。
- 修正建议：
  - 保留能力描述。
  - 把“对 MacWatch 价值最高”移到建议段落。

### 4.7 GPU 模块

- 原文位置：`Stats_功能梳理.md:306-321`
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - 默认关闭：`State = 0`。[GPU/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/GPU/config.plist:1)
  - `InfoReader` 读取 utilization、renderer、tiler、温度、风扇、core/memory clock。[GPU/reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/GPU/reader.swift:139)
  - Apple Silicon 上额外读取 ANE power/utilization 与 DCP swap 估算 FPS。[GPU/reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/GPU/reader.swift:242) [GPU/reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/GPU/reader.swift:258)
- 修正建议：
  - 加上“依赖平台与驱动提供的 `PerformanceStatistics`/IOReport 字段”。

### 4.8 Bluetooth 模块

- 原文位置：`Stats_功能梳理.md:327-337`
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - 默认关闭：`State = 0`。[Bluetooth/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Bluetooth/config.plist:1)
  - `DevicesReader` 使用 CoreBluetooth、IOBluetooth、`system_profiler SPBluetoothDataType`、`pmset -g accps -xml`。[Bluetooth/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Bluetooth/readers.swift:14) [Bluetooth/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Bluetooth/readers.swift:276) [Bluetooth/readers.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Bluetooth/readers.swift:383)
  - 原文中的 “IORegistry HID 设备” 这一点在 Bluetooth 模块抽查中没有看到明确字面证据，至少不应直接下结论。
- 修正建议：
  - 将该条改为“包含多种系统来源，包括 CoreBluetooth、IOBluetooth、`system_profiler`、`pmset` 等”。

### 4.9 Clock 模块

- 原文位置：`Stats_功能梳理.md:343`
- 核验结论：`属实`
- 源码依据：
  - 默认关闭：`State = 0`。[Clock/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Clock/config.plist:1)
  - 其核心 reader 为 `ClockReader`，定位就是时间显示。[Clock/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Clock/main.swift:100)
- 修正建议：
  - 可保留。

### 4.10 Remote 模块与 SystemStats

- 原文位置：`Stats_功能梳理.md:347-349`
- 核验结论：`部分属实 / 表述过强`
- 源码依据：
  - 默认关闭：`State = 0`。[Remote/config.plist](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Remote/config.plist:1)
  - `Reader.callback` 确实会把实现 `RemoteType` 的值通过 `SystemStats.shared.send` 发送。[reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:118)
  - 但当前 Remote 不只是“外部远程监控/控制”，而是完整云端产品接入：OAuth、MQTT、设备注册、监控与控制开关、账号 plan、远端机器/主机列表等。[SystemStats.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/SystemStats.swift:34) [Remote/main.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Modules/Remote/main.swift:1)
- 修正建议：
  - 把 Remote 段落改成“当前源码已接入 System Stats 云服务，而非仅本地远程接口预留”。

## 5. 设置、Popup、通知与组合菜单

### 5.1 第 353-365 行

- 原文位置：`Stats_功能梳理.md:353-365`
- 原始表述摘要：模块启停、widget 类型、显示样式、阈值、标题、单位、刷新间隔、popup、通知、登录启动、Dock 图标、温度单位、导入导出重置、macOS Widgets、组合模块。
- 核验结论：`属实`
- 源码依据：
  - AppSettings 中有更新、温度、Dock、启动项、macOS widgets、combined modules、remote、导入/导出/重置。[AppSettings.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/Views/AppSettings.swift:99)
  - `Store.export/import/reset` 都存在。[Store.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/Store.swift:98)
  - `CombinedView` 实现组合菜单项与组合 popup/点击行为。[CombinedView.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Stats/Views/CombinedView.swift:15)
- 修正建议：
  - 建议把“完整设置体系”写成“设置覆盖面较广”，更客观。

## 6. Stats 对 MacWatch 的可复用清单

### 6.1 第 371-386 行

- 原文位置：`Stats_功能梳理.md:371-386`
- 原始表述摘要：高/中/低复用程度判断。
- 核验结论：`属于建议，不是源码事实`
- 源码依据：
  - 这部分是面向 MacWatch 的技术选型意见，源码不能直接证明“高/中/低”。
- 修正建议：
  - 整节前增加“以下为面向 MacWatch 的复用评估，不是 Stats 源码事实”。

## 7. 需要重点改造的地方

### 7.1-7.5 全节

- 原文位置：`Stats_功能梳理.md:390-436`
- 原始表述摘要：从实时菜单栏工具改造成历史监控工具，改用 SQLite/GRDB/SwiftData，设计统一指标命名，采样与落库解耦，默认本地隐私优先。
- 核验结论：`属于建议，不是源码事实`
- 源码依据：
  - 源码只证明 Stats 当前实现是什么，不证明 MacWatch 必须如何改。
  - 唯一可直接引用的事实是：Reader callback 同时牵涉 callback / DB / remote；DB TTL 1 小时；Stats 确有外部联网能力。[reader.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/module/reader.swift:113) [DB.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/DB.swift:19) [SystemStats.swift](/Users/lzc/TNTprojectZ/AprojectZ/MacWatch/Vendor/Stats/Kit/plugins/SystemStats.swift:29)
- 修正建议：
  - 整节应明确加标题：“面向 MacWatch 的改造建议（非源码事实）”。

## 8. 对 MacWatch 的总体结论

### 8.1 第 440-449 行

- 原文位置：`Stats_功能梳理.md:440-449`
- 原始表述摘要：Stats 提供了大部分底层能力，MacWatch 可基于采集代码和模块架构快速落地，但应聚焦历史数据库、趋势图、异常事件、轻量菜单栏与本地隐私优先。
- 核验结论：`前半句部分属实，后半句属于建议`
- 源码依据：
  - 前半句关于底层能力范围与模块化架构，源码基本支持。
  - 后半句是面向 MacWatch 的产品/架构建议，不是 Stats 事实。
- 修正建议：
  - 拆成两段：
    - “源码事实总结”
    - “面向 MacWatch 的建议总结”

---

## 建议改写原则

后续若要修订原文，建议统一遵循以下规则：

1. 先写“源码事实”，再写“推论/建议”。
2. 只要一句话里出现“适合/不适合/建议/MVP/价值最高/核心工作应集中在”，就不应归入源码事实段。
3. 对受平台影响的模块能力，要补充限定语：
   - “视平台/驱动/权限/设备类型而定”
   - “源码存在该路径，但不代表所有机器都稳定提供该指标”
4. 对联网能力要明确写出外部端点与用途：
   - 更新检查：`api.mac-stats.com`
   - 公网 IP：`api.mac-stats.com/ip`
   - 远程服务：`system-stats.com` 相关域名

---

## 最终判断

这份原文可以作为“源码导读 + MacWatch 迁移思考”的草稿，但目前不适合直接当成严格的事实文档使用，主要问题有三类：

- 一部分能力描述是对源码的合理概括，但措辞过满，容易让人误以为所有平台都等价支持。
- 一部分实现边界没有写清，例如 DB 只是有 1 小时 TTL 的短期历史实现，而不是被源码明示定义为“长期不可用”的技术方案。
- 从第 6 节开始，文风已经明显从“源码分析”切换到“MacWatch 设计建议”，但没有显式分层，后续开发者容易把建议误读为现状。

如果要继续用于后续开发，建议下一步直接基于本报告修订原文，把“事实层”和“建议层”拆开。
