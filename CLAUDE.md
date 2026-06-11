# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language and source-of-truth

- 默认使用中文回答、说明计划和汇报结果；代码标识、路径、命令、日志和系统 API 名称可以保留英文。
- 需求拆解、架构设计、开发计划或实现前，先按需查阅 `docs/origin` 中的相关章节；不要默认整篇读取。
- `docs/.del_tmp` 是忽略目录，不要参考其内容。
- 修改工程结构、脚本或阶段状态后，如影响上手流程或验证方式，应同步更新 `README.md`。

## Common commands

```bash
# Initialize the Stats submodule if missing
git submodule update --init --recursive

# Build debug package
./scripts/build.sh

# Run full test suite and Stats boundary scan
./scripts/test.sh

# Run one test target
swift test --filter MacWatchCoreTests

# Run one test case
swift test --filter TemperatureSchedulerTests/testName

# Package debug .app to dist/MacWatch.app
./scripts/package_app.sh

# Package release .app
./scripts/package_app.sh --configuration release

# Launch the packaged debug app
./scripts/run.sh

# Emit one temperature diagnostics JSON Lines probe
./scripts/probe_temperature_once.sh

# Run stage 7 acceptance; summary defaults to dist/stage7-summary.json
./scripts/run_stage7_acceptance.sh

# Run distribution preflight against a bundle
./scripts/preflight_distribution.sh dist/MacWatch.app
```

`./scripts/test.sh` runs `swift test` and then `./scripts/verify_stats_boundary.sh`. The boundary scan rejects forbidden Stats lifecycle, networking, updater, notification, widget, LevelDB, and SMC-write/helper patterns outside the allowed adapter boundary.

## Project architecture

MacWatch is a Swift Package for macOS 13+ focused on local Apple Silicon Mac temperature monitoring. It does not upload data and should not record user filenames, network contents, window titles, or process lists.

`Package.swift` defines these main targets:

- `MacWatchApp` executable depends on `MacWatchCore` and `StatsAdapter`. It owns the SwiftUI app, `AppDelegate`, menu bar entry, popup/dashboard/settings/detail views, first-run guide, and acceptance CLI entry points.
- `MacWatchCore` library owns domain logic: temperature models, probes protocol, capabilities, sampling scheduler, `SampleBus`, live state, settings, lifecycle handling, SQLite-backed current-session history, trend queries, statistics, and downsampling.
- `StatsAdapter` library depends on `MacWatchCore` and `StatsAdapterIOHID`. It isolates read-only hardware collection for CPU, GPU, memory, SSD/NAND, battery, system, and sensor temperatures.
- `StatsAdapterIOHID` is the minimal Objective-C HID sensors bridge linked to Foundation and IOKit.

Runtime flow is intentionally layered:

1. `StatsAdapter` creates read-only `TemperatureProbe` implementations.
2. `MacWatchCore` validates samples, detects capability/status, schedules fast/slow sampling, emits sample/gap/capability events through `SampleBus`, and writes current-session history.
3. `MacWatchApp` builds `MacWatchRuntime`, observes live state/settings/history revisions, formats temperatures, and renders SwiftUI/menu bar UI.

Keep shared domain behavior in `MacWatchCore`, system collection in `StatsAdapter`, and presentation/runtime wiring in `MacWatchApp`.

## Product and implementation boundaries

- MVP scope is temperature collection, capability detection, menu bar/popup/dashboard/details/settings UI, first-run guide, current app-session history, and trend viewing.
- Do not add Post-MVP features unless explicitly requested: resource monitoring, process statistics, alerts, export, cloud sync, remote monitoring, widgets, fan control, privileged helpers, or long-term cross-session history.
- UI must not directly access IOKit, SMC, IOReport, DiskArbitration, SQLite, networking, or `Vendor/Stats`; it should go through MacWatch runtime/store/repository/settings abstractions.
- `StatsAdapter` must stay read-only: no database writes, notifications, networking, UI state, privileged helpers, fan control, or SMC writes.
- `Vendor/Stats` is a pinned read-only upstream reference, not a stable SDK. Do not modify it by default; migrate or wrap only necessary read-only collection logic in MacWatch-owned code.
- Unreadable temperature metrics must surface explicit states such as `unsupported`, `readFailed`, or `stale`; never show them as `0°C`, blank, stale old values, or estimates.
- Internal temperatures are Celsius; UI converts units according to settings.
- Probe failures must not crash the app, and one metric failure must not block other metrics.
- Sleep, wake, pause, app exit, and consecutive read failures create data gaps; do not synthesize samples or draw trend lines across gaps.

## Validation expectations

- For core logic, collection adapters, history, scheduler, settings, or UI presentation changes, run `./scripts/test.sh` unless the user asks otherwise.
- For app launch, window/menu bar/popup, first-run guide, acceptance CLI, resource/network boundary, or distribution behavior, also run the relevant script such as `./scripts/run_stage7_acceptance.sh` or `./scripts/preflight_distribution.sh`.
- Stage 7 acceptance includes real hardware, resources, network, Stats boundary, and distribution preflight checks. Missing Developer ID or notarization credentials may make distribution preflight `blocked`; that is not a temperature pipeline failure.
- If real hardware temperature reads cannot be verified in the current environment, validate domain behavior with fake probes, fixtures, or mock repositories and clearly state the unverified real-device coverage.
