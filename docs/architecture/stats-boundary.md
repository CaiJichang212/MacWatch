# StatsAdapter Boundary

## Upstream Position

- `Vendor/Stats` 当前固定版本为 `v3.0.1`。
- `Vendor/Stats` 在 MacWatch 仓库中保持只读，不承载 MacWatch 业务代码。
- MacWatch 通过 `StatsAdapter` 隔离未来会复用或移植的只读采集逻辑。

## Allowed Read-Only References

- HID Sensors 读取思路
- SMC 只读温度读取思路
- Battery IORegistry 温度读取逻辑
- NVMe SMART 内置 SSD/NAND 温度解析逻辑
- 必要的 IORegistry、IOReport 读取片段

## Prohibited Integrations

- Stats `Reader`
- Stats `Module` 生命周期
- Stats `DB.shared`
- LevelDB
- Remote
- MQTT
- OAuth
- Updater
- 通知
- Widget
- LaunchAtLogin helper
- SMC privileged helper
- SMC 写操作

## Adapter Constraints

- `StatsAdapter` 不写数据库。
- `StatsAdapter` 不发通知。
- `StatsAdapter` 不访问网络。
- `StatsAdapter` 不持有 UI 状态。
- 阶段 1 不 import 或编译 `Vendor/Stats` 源码。

## Verification

- `./scripts/build.sh` 用于验证阶段 1 工程骨架可构建。
- `./scripts/test.sh` 用于验证单元测试和边界扫描一起通过。
- `./scripts/verify_stats_boundary.sh` 用于独立验证禁止接入项没有进入生产/测试源码。
