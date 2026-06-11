# Stats 温度采集源码分析报告

本文分析 `Vendor/Stats` 中与 MacBook 温度检测/获取相关的源码路径，重点覆盖 CPU、GPU、内置 SSD/NAND、电池、系统/传感器温度。

## 0. 事实核验说明

本报告以 `Vendor/Stats` 当前源码为依据，只描述源码中能确认的读取路径、key catalog、回调连接和数据换算。以下表述已在本次核验中收紧，避免超出源码证据：

- CPU `TemperatureReader` 的回调连接到 CPU popup；报告不再断言它一定用于菜单栏显示。
- Disk 模块只解析 NVMe SMART 的 controller temperature；NAND channel/SMC NAND 传感器属于 Sensors catalog 中的另一条路径。
- HID 传感器列表只是 Stats 对已知 HID `Product` 名的命名映射；实际出现哪些传感器取决于运行设备枚举结果和 `Sensors_hid` 设置。
- GPU 模块在 Apple Silicon 上没有显式 SMC/HID 温度 fallback；Apple Silicon 多核心 GPU 温度和 Average/Hottest GPU 的源码依据主要在 Sensors 模块。

## 1. 结论摘要

Stats 的温度来源不是单一接口，而是多条链路组合：

| 指标 | 主要源码 | 主要机制 | 备注 |
| --- | --- | --- | --- |
| CPU 温度 | `Modules/CPU/readers.swift`、`Modules/Sensors/readers.swift`、`Modules/Sensors/values.swift` | SMC 读固定 key；Apple Silicon 还可用 IOHID 传感器补充 | CPU 模块向 CPU popup 提供一个代表温度；Sensors 模块提供完整传感器列表与平均/最高 CPU |
| GPU 温度 | `Modules/GPU/reader.swift`、`Modules/Sensors/readers.swift`、`Modules/Sensors/values.swift` | IOAccelerator `PerformanceStatistics["Temperature(C)"]`；Intel/AMD 回退 SMC；Apple Silicon Sensors 模块用 SMC/HID 列表 | GPU 模块主要服务 GPU 信息；Sensors 模块可计算 Average/Hottest GPU |
| 内置 SSD/NAND 温度 | `Modules/Disk/readers.swift`、`Modules/Disk/header.h`、`Modules/Sensors/values.swift` | NVMe SMART log 的 controller temperature；Apple Silicon Sensors 还枚举 `TH0x` / HID NAND 通道 | Disk 模块只解析 SMART controller temperature；Sensors 模块另有 SMC/HID NAND 相关传感器 |
| 电池温度 | `Modules/Battery/readers.swift`、`Modules/Sensors/values.swift` | AppleSmartBattery IORegistry 属性 `Temperature`；Sensors 模块也可读取 SMC/HID 电池传感器 | Battery 模块将原始值除以 100 得到 °C |
| 系统/传感器温度 | `Modules/Sensors/readers.swift`、`Modules/Sensors/reader.m`、`Modules/Sensors/values.swift`、`SMC/smc.swift` | SMC 全 key 枚举 + 已知 key 表；Apple Silicon IOHID 事件传感器；计算平均/最高值 | 是 Stats 温度传感器总入口 |

## 2. 平台与硬件能力识别

Stats 先通过 `Kit/plugins/SystemKit.swift` 建立设备信息：

- `SystemKit.shared.device.platform` 用 CPU 名称识别 `.intel`、`.m1`、`.m2`、`.m3`、`.m4`、`.m5` 及 Pro/Max/Ultra 变体。
- `getCPUInfo()` 使用 `sysctlbyname("machdep.cpu.brand_string")`、`host_info()`、AppleARMPE IORegistry 信息识别 CPU 核心组成。
- `getGPUInfo()` 调用 `/usr/sbin/system_profiler SPDisplaysDataType -json` 获取 GPU 型号、供应商、核心数等静态信息。
- `getDiskInfo()` 调用 `diskutil list -plist` / `diskutil info -plist` 获取启动磁盘信息。

这些信息不会直接返回温度，但会决定 Sensors 模块加载哪些 SMC key，例如 Apple Silicon 不同代际的 CPU/GPU 温度 key 不同。

## 3. SMC 读取基础设施

温度采集的核心底层之一是 `SMC/smc.swift`：

1. 初始化时匹配 `AppleSMC` 服务：
   - `IOServiceMatching("AppleSMC")`
   - `IOServiceGetMatchingServices(...)`
   - `IOServiceOpen(...)`
2. `getValue(_ key: String)` 调用内部 `read(&val)` 获取 SMC key 信息和值。
3. `read(&val)` 分两步：
   - `SMCKeys.readKeyInfo` 读取 key 的数据大小和数据类型。
   - `SMCKeys.readBytes` 读取原始 bytes。
4. 根据 SMC 数据类型转换为 `Double`：
   - `ui8`、`ui16`、`ui32` 直接转整数。
   - `sp78`、`sp87`、`sp96`、`spb4` 等 fixed-point 格式按比例换算。
   - `flt ` 转 `Float`。
   - `fpe2` 用于风扇转速等。
5. `getAllKeys()` 先读 `#KEY`，再通过 `SMCKeys.readIndex` 遍历全部 SMC key。

温度 key 通常以 `T` 开头。Sensors 模块会用 `getAllKeys()` 发现设备上实际存在的 key，再结合内置 key 表过滤和命名。

## 4. CPU 温度

### 4.1 CPU 模块的代表温度

源码：`Modules/CPU/readers.swift` 的 `TemperatureReader`。

`TemperatureReader.setup()` 按平台预置 Apple Silicon CPU 核心温度 key：

- M1：`Tp09`、`Tp0T`、`Tp01`、`Tp05`、`Tp0D`、`Tp0H`、`Tp0L`、`Tp0P`、`Tp0X`、`Tp0b`
- M2：`Tp1h`、`Tp1t`、`Tp1p`、`Tp1l`、`Tp01`、`Tp05`、`Tp09`、`Tp0D`、`Tp0X`、`Tp0b`、`Tp0f`、`Tp0j`
- M3：`Te05`、`Te0L`、`Te0P`、`Te0S`、`Tf04`、`Tf09`、`Tf0A`、`Tf0B`、`Tf0D`、`Tf0E`、`Tf44`、`Tf49`、`Tf4A`、`Tf4B`、`Tf4D`、`Tf4E`
- M4：`Te05`、`Te09`、`Te0H`、`Te0S`、`Tp01`、`Tp05`、`Tp09`、`Tp0D`、`Tp0V`、`Tp0Y`、`Tp0b`、`Tp0e`
- M5：`Tp00`、`Tp04`、`Tp08`、`Tp0C`、`Tp0G`、`Tp0K`、`Tp0O`、`Tp0R`、`Tp0U`、`Tp0X`、`Tp0a`、`Tp0d`、`Tp0g`、`Tp0j`、`Tp0m`、`Tp0p`、`Tp0u`、`Tp0y`

`TemperatureReader.read()` 的读取优先级：

1. 依次尝试 SMC key：`TC0D`、`TC0E`、`TC0F`、`TC0P`、`TC0H`。
2. 每个值要求 `< 110`，避免异常值。
3. 如果这些传统 CPU key 不可用，则遍历 `setup()` 中的平台 key 列表。
4. 对可读值求平均，作为 CPU 温度回调。

因此 CPU 模块的温度是一个“代表值”：优先传统 CPU 传感器，否则 Apple Silicon 各核心温度平均。源码中该 reader 的回调接到 CPU popup，并不能单独证明菜单栏一定显示该温度。

### 4.2 Sensors 模块中的 CPU 传感器列表

源码：`Modules/Sensors/values.swift` 和 `Modules/Sensors/readers.swift`。

`SensorsList` 定义了大量 CPU 温度 key：

- Intel/通用：`TC0D`、`TC0E`、`TC0F`、`TC0H`、`TC0P`、`TCAD`、`TC%c`、`TC%C`。
- Apple Silicon M1/M2/M3/M4/M5：按代际定义 `Tp*`、`Te*`、`Tf*` 等 CPU core key，并将核心温度标记为 `average: true`。

`SensorsReader.sensors()` 处理流程：

1. `SMC.shared.getAllKeys()` 获取实际存在的全部 SMC key。
2. 按当前平台过滤 `SensorsList`。
3. 匹配固定 key 和带 `%` 通配符的 key。
4. 对匹配到的 key 调用 `SMC.shared.getValue(sensor.key)` 读取初值。
5. 过滤异常温度：`value == 0` 或 `value > 110` 的温度传感器会被剔除。
6. 最后追加计算传感器：`Average CPU`、`Hottest CPU`。

`SensorsReader.read()` 后续刷新时：

- 对非 HID、非计算传感器再次用 SMC 读取。
- CPU 温度如果 `< 10` 或 `> 120`，会保留旧值，注释说明是为了规避 M2 broken sensors。
- 收集 `group == .CPU && type == .temperature && average == true` 的值，计算 `Average CPU` 和 `Hottest CPU`。

### 4.3 Apple Silicon HID CPU 温度补充

源码：`Modules/Sensors/reader.m`、`Modules/Sensors/readers.swift`、`Modules/Sensors/values.swift`。

当 `Sensors_hid` 设置开启且架构为 `arm64` 时，Stats 会读取 Apple Silicon IOHID 传感器：

1. `m1Preset(type: .temperature)` 返回：
   - page = `0xff00`
   - usage = `0x0005`
   - eventType = `kIOHIDEventTypeTemperature`
2. Objective-C 函数 `AppleSiliconSensors(page, usage, type)`：
   - 创建 `IOHIDEventSystemClientRef`。
   - 设置 matching 字典：`PrimaryUsagePage` 和 `PrimaryUsage`。
   - `IOHIDEventSystemClientCopyServices()` 获取服务列表。
   - 对每个 service 读取 `Product` 作为传感器名。
   - `IOHIDServiceClientCopyEvent(service, type, 0, 0)` 获取事件。
   - `IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(type))` 得到温度值。
3. `HIDSensorsList` 将 `pACC MTR Temp Sensor%` 映射为 CPU performance core，将 `eACC MTR Temp Sensor%` 映射为 CPU efficiency core。
4. `SensorsReader.read()` 将 HID CPU 温度加入 CPU 平均/最高值计算。

## 5. GPU 温度

Stats 有两条 GPU 温度路径。

### 5.1 GPU 模块读取 IOAccelerator 温度

源码：`Modules/GPU/reader.swift` 的 `InfoReader`。

`InfoReader.read()` 通过 `fetchIOService(kIOAcceleratorClassName)` 获取 IOAccelerator 服务列表，读取每个 accelerator 的 `PerformanceStatistics`：

- 优先取 `stats["Temperature(C)"]`。
- 同时读取 GPU 使用率、Renderer/Tiler 使用率、风扇、核心频率、显存频率等。

按 `IOClass` 做平台/厂商判断：

- NVIDIA：`ioClass == "nvaccelerator"` 或包含 `nvidia`。
- AMD：`ioClass` 包含 `amd`。
  - 如果 `PerformanceStatistics` 没有温度或温度为 0，则回退 SMC key `TGDD`，且排除 `128` 异常值。
- Intel：`ioClass` 包含 `intel`。
  - 如果没有温度或温度为 0，则回退 SMC key `TCGC`，且排除 `128` 异常值。
- Apple Silicon：`ioClass` 包含 `agx`。
  - 识别为 integrated GPU，但该文件中没有直接用 AGX 的 SMC/HID key 读取温度；温度主要依赖 `PerformanceStatistics["Temperature(C)"]` 是否提供。

### 5.2 Sensors 模块中的 GPU 温度

`Modules/Sensors/values.swift` 中定义了 GPU 温度 key：

- 通用/Intel/AMD：`TCGC`、`TG0D`、`TGDD`、`TG0H`、`TG0P`。
- Apple Silicon：M1/M2/M3/M4/M5 分别有 `Tg*` 或 `Tf*` GPU core key。
- HID：`GPU MTR Temp Sensor%`。

`SensorsReader` 会：

1. 用 SMC key 表匹配并读取 GPU 温度。
2. HID 开启时读取 `GPU MTR Temp Sensor%`。
3. 对 `average == true` 的 GPU core 温度计算 `Average GPU` 和 `Hottest GPU`。

因此，若关注 Apple Silicon GPU 多核心温度、Average/Hottest GPU 等传感器维度，源码依据主要在 Sensors 模块；GPU 模块自身主要是 GPU 状态/利用率视图中的温度字段。

## 6. 内置 SSD/NAND 温度

Stats 有两类磁盘温度来源。

### 6.1 Disk 模块读取 NVMe SMART 温度

源码：`Modules/Disk/readers.swift`、`Modules/Disk/header.h`。

`CapacityReader.getSMARTDetails(for BSDName:)` 的流程：

1. 检查设置 `Disk_SMART` 是否开启。
2. 用 `IOBSDNameMatching(...)` 根据 BSD 名称找到磁盘 IOService。
3. 沿 IORegistry 父节点向上查找，直到符合 `kIOBlockStorageDeviceClass`。
4. 检查属性 `NVMe SMART Capable == true`。
5. 调用 `IOCreatePlugInInterfaceForService(...)` 创建 NVMe SMART 插件接口。
6. 通过 `QueryInterface(... kIONVMeSMARTInterfaceID ...)` 获取 `IONVMeSMARTInterface`。
7. 调用 `SMARTReadData(smartInterface, &smartData)` 读取 `nvme_smart_log`。
8. 从 `smartData.temperature[2]` 读取 NVMe 温度：源码先按 `[temperature.1, temperature.0]` 组装两个字节，再用 `UInt16(bigEndian:)` 转换。
9. 转换：NVMe SMART 温度单位是 Kelvin，源码返回 `Int(UInt16(bigEndian: temperature) - 273)`，即摄氏度。

`header.h` 定义了 `nvme_smart_log` 结构，其中包含：

- `temperature[2]`：控制器综合温度。
- `temp_sensor[8]`：额外温度传感器槽位，但当前 `readers.swift` 没有解析这些槽位。

结论：Disk 模块读取的是 NVMe SMART controller temperature，不是逐 NAND channel 温度。

### 6.2 Sensors 模块中的 NAND/磁盘温度

`Modules/Sensors/values.swift` 还定义了：

- Apple Silicon SMC：`TH0x`，名称为 `NAND`，分组为 `.system`。
- 通用磁盘相关 SMC：`TH%A`、`TH%B`、`TH%C`，名称为 `Disk % (A/B/C)`。
- HID：`NAND CH% temp`，名称为 `Disk %s`。注意源码中该项 group 写成 `.GPU`，从语义上看更像磁盘/NAND 温度，但 Stats 当前表中就是这样定义。

因此 Stats 对内置 SSD/NAND 温度的源码覆盖包括：

- Disk 模块：NVMe SMART controller temperature，并在 Disk popup/preview 中作为 SMART 温度使用。
- Sensors 模块：传感器 catalog 中存在 SMC `TH0x` / `TH%*` 和 HID `NAND CH% temp` 这类平台传感器；是否展示取决于 Sensors 模块运行、HID 设置和 UI 传感器开关。

## 7. 电池温度

### 7.1 Battery 模块读取 AppleSmartBattery 温度

源码：`Modules/Battery/readers.swift` 的 `UsageReader`。

初始化时：

- `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))` 获取电池服务。

读取时：

1. `IOPSCopyPowerSourcesInfo()` / `IOPSCopyPowerSourcesList()` / `IOPSGetPowerSourceDescription()` 获取电源状态、电量、剩余时间等。
2. 通过 `IORegistryEntryCreateCFProperty(self.service, "Temperature" as CFString, ...)` 读取 AppleSmartBattery 的 `Temperature` 属性。
3. `getTemperature()` 返回 `value / 100.0`。

结论：Battery 模块中的电池温度单位换算是 centi-degree Celsius 到 Celsius。

### 7.2 Sensors 模块中的电池温度

`Modules/Sensors/values.swift` 中也有电池温度：

- Intel/通用：`TB1T`，名称 `Battery`。
- Apple Silicon：`TB1T`、`TB2T`，名称 `Battery 1`、`Battery 2`。
- HID：`gas gauge battery`，名称 `Battery`。

这些由 `SensorsReader` 通过 SMC 或 HID 读取，属于系统传感器列表的一部分。

## 8. 系统/传感器温度总入口

源码：`Modules/Sensors/readers.swift`、`Modules/Sensors/values.swift`。

### 8.1 传感器枚举

`SensorsReader.sensors()` 是 Stats 的通用传感器枚举入口：

1. `SMC.shared.getAllKeys()` 获取全部 SMC key。
2. 仅保留以 `T`、`V`、`P`、`I` 开头的 key，分别代表温度、电压、功率、电流。
3. 根据 `SystemKit.shared.device.platform` 过滤 `SensorsList`。
4. 匹配固定 key。
5. 对包含 `%` 的 key 做 0 到 9 的展开匹配。
6. 未知 key 如果是 `T/V/P/I` 前缀，也包装为 `.unknown` 传感器。
7. 初次读取每个传感器值。
8. 过滤异常：温度 `0` 或 `> 110`、电流 `> 100` 等。
9. Apple Silicon 下可追加 HID 传感器和 IOReport 功率传感器。
10. 追加计算传感器。

### 8.2 已知系统温度 key

`SensorsList` 中系统/传感器温度包括但不限于：

- Ambient：`TA%P`
- Heatpipe：`Th%H`
- Thermal zone：`TZ%C`
- Mainboard：`Tm0P`
- Powerboard：`Tp0P`
- Battery：`TB1T` / `TB2T`
- Airport：`TW0P`
- Display：`TL0P`
- Thunderbolt：`TI%P`、`TTLD`、`TTRD`
- Disk：`TH%A`、`TH%B`、`TH%C`
- Northbridge：`TN0D`、`TN0H`、`TN0P`
- Apple Silicon NAND：`TH0x`
- Apple Silicon Airflow：`TaLP`、`TaRF`
- Apple Silicon Memory：`Tm02`、`Tm06`、`Tm08`、`Tm09`、M4 的 `Tm0p`、`Tm1p`、`Tm2p`

### 8.3 HID 传感器

Apple Silicon HID 传感器通过 Objective-C 桥接实现：

- `AppleSiliconSensors(page, usage, type)` 返回 `[ProductName: value]`。
- 温度匹配参数是 `PrimaryUsagePage = 0xff00`、`PrimaryUsage = 0x0005`、`kIOHIDEventTypeTemperature`。
- `HIDSensorsList` 为已知 HID 产品名提供命名映射，覆盖 CPU、GPU、SOC、ANE、ISP、PMGR、PMU、电池、NAND channel 等；实际是否出现取决于 `AppleSiliconSensors(...)` 枚举到的 HID service。

### 8.4 计算传感器

`initCalculatedSensors()` 和 `read()` 中会生成/刷新：

- `Average CPU`
- `Hottest CPU`
- `Average GPU`
- `Hottest GPU`
- `Average SOC`
- `Hottest SOC`
- 风扇相关计算项
- 系统功耗累计项

CPU/GPU 平均值只使用 `average == true` 的核心温度传感器；HID 开启时还会加入 `pACC/eACC/GPU MTR` 传感器。

## 9. 异常值与有效性处理

Stats 对温度有几类过滤/保护：

- 初始化传感器列表时，温度 `0` 或 `> 110` 会被过滤。
- HID 读取时，要求 `0 <= value < 300`，最终初始化列表仍会过滤到 `< 110`。
- CPU SMC 刷新时，如果 CPU 温度 `< 10` 或 `> 120`，保留旧值，用于规避 M2 broken sensors。
- CPU 模块代表温度读取传统 key 时要求 `< 110`。
- GPU Intel/AMD SMC 回退时排除 `128`。
- NVMe SMART 温度没有额外范围校验，只做 Kelvin 到 Celsius 转换。
- Battery IORegistry 温度没有额外范围校验，只做 `/100.0` 换算。

## 10. 对 MacWatch 复用的启示

基于 Stats 源码，MacWatch MVP 可按以下方式复用/迁移，只保留只读采集逻辑：

1. SMC 只读能力：迁移 `AppleSMC` open/read、SMC fixed-point 解码、`getAllKeys()`、`getValue()`，禁止迁移 fan write/helper。
2. CPU 温度：优先复用 `TemperatureReader` 的 key 优先级和 Apple Silicon key 表；Sensors 完整列表用于能力检测和多指标补齐。
3. GPU 温度：Apple Silicon 更建议从 Sensors 的 SMC/HID GPU key 获取核心温度；Intel/AMD 可参考 GPU 模块的 IOAccelerator + SMC fallback。
4. SSD/NAND：NVMe SMART 可复用 Disk 模块只读 `SMARTReadData` 流程；NAND channel/SMC `TH0x` 可从 Sensors 模块补充。
5. 电池：优先复用 `AppleSmartBattery` 的 `Temperature / 100.0`；Sensors 中 `TB1T/TB2T` 和 HID `gas gauge battery` 可作为补充来源。
6. 系统/传感器：复用 `SensorsList` 与 `HIDSensorsList` 的 key catalog，但需要修正或重新归类不适合 MacWatch 的项，例如 HID `NAND CH% temp` 当前在 Stats 中被标为 `.GPU`。
7. 边界：不要复用 Stats 的完整 Reader/Module 生命周期、DB、通知、Widget、网络、Updater、SMC 写操作或 privileged helper。

## 11. 关键源码索引

- `Vendor/Stats/SMC/smc.swift`：SMC 打开、读取、解码、枚举 key；同文件也包含风扇写操作，MacWatch 只能参考只读部分。
- `Vendor/Stats/Modules/CPU/readers.swift`：CPU 代表温度 `TemperatureReader`，以及 CPU 负载/频率/限制等无关逻辑。
- `Vendor/Stats/Modules/GPU/reader.swift`：GPU IOAccelerator 信息读取，包含 `PerformanceStatistics["Temperature(C)"]` 和 Intel/AMD SMC fallback。
- `Vendor/Stats/Modules/Disk/readers.swift`：Disk 容量、SMART、活动读取；SMART 温度在 `getSMARTDetails(for:)`。
- `Vendor/Stats/Modules/Disk/header.h`：NVMe SMART log 结构和 `IONVMeSMARTInterface` 定义。
- `Vendor/Stats/Modules/Battery/readers.swift`：AppleSmartBattery 信息读取，包含电池温度。
- `Vendor/Stats/Modules/Sensors/readers.swift`：传感器枚举、读取、HID 接入、平均/最高计算。
- `Vendor/Stats/Modules/Sensors/reader.m`：Apple Silicon IOHID 传感器 Objective-C 桥接。
- `Vendor/Stats/Modules/Sensors/values.swift`：SMC/HID 传感器 key catalog、分组、名称、单位格式化。
- `Vendor/Stats/Kit/plugins/SystemKit.swift`：平台、CPU/GPU/Disk 静态信息识别。
