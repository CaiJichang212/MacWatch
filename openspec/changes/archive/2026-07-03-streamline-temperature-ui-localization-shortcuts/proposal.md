## Why

当前 Popup 和 Dashboard 重复展示数据来源、正常状态和逐项更新时间等实现性信息，使用户难以快速判断各硬件设备的当前温度。MacWatch 还缺少应用内中英文切换和标准 macOS 窗口快捷键，影响日常使用效率与系统一致性。

## What Changes

- 精简 Popup 与 Dashboard，只突出当前最高温度和各硬件设备的关键温度；移除正常读数的 `Valid`、数据来源和逐项更新时间等重复信息。
- Popup 与 Dashboard 仅显示一次整体更新时间；异常指标继续明确展示“不支持”“读取失败”或“数据已过期”及必要原因，且不得伪装为有效温度。
- 收紧 Popup 和主窗口的默认尺寸、卡片高度、间距与信息层级，减少无效空白，同时保持可读性与主窗口合理的缩放能力。
- 保留详情页的来源、采样状态、更新时间、统计与趋势等诊断信息，仅做与新视觉层级一致的小幅调整。
- 在设置中增加“跟随系统 / 中文 / English”语言选项，默认跟随 macOS；切换后立即更新应用内可见文本，无需重启。
- 接入标准 macOS 命令：`⌘W` 关闭当前窗口、`⌘,` 打开设置、`⌘Q` 退出应用；不新增其他快捷键。
- 更新对应展示、设置持久化、窗口命令和本地化测试，并在需要时同步 README 的使用说明。

## Capabilities

### New Capabilities

- `temperature-overview-ui`: 规定 Popup、Dashboard 与温度详情页的信息层级、异常状态展示和紧凑布局行为。
- `app-localization`: 规定应用语言选项、默认跟随系统、持久化和即时切换行为。
- `macos-window-commands`: 规定关闭窗口、打开设置和退出应用的标准 macOS 菜单命令与快捷键。

### Modified Capabilities

无。当前 OpenSpec 尚无已建立的主规格，本次以新能力规格承接现有产品文档的相关要求。

## Impact

- 主要影响 `Sources/MacWatchApp` 中 Popup、Dashboard、详情页、设置页、展示格式化、主窗口与菜单命令组装。
- `MacWatchCore` 的 `AppSettings` 与 `SettingsStore` 需要新增兼容旧数据的语言偏好字段。
- Swift Package 需要声明并打包中英文 localization resources；不新增第三方运行时依赖。
- 现有采集、能力检测、会话历史、StatsAdapter 边界和温度领域模型保持不变。
- `Tests/MacWatchAppTests` 与 `Tests/MacWatchCoreTests` 需要覆盖精简展示、异常状态、本地化即时生效、旧设置迁移和快捷键命令。
