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

# Package an existing binary or custom output bundle
./scripts/package_app.sh --skip-build --binary .build/arm64-apple-macosx/debug/MacWatchApp --output dist/MacWatch.app

# Launch the packaged debug app
./scripts/run.sh

# Emit one temperature diagnostics JSON Lines probe
./scripts/probe_temperature_once.sh

# Equivalent direct CLI probe
swift run MacWatchApp --probe-temperature-once

# Run a single acceptance scenario
swift run MacWatchApp --acceptance-run probe-status

# Run stage 7 acceptance; summary defaults to dist/stage7-summary.json
./scripts/run_stage7_acceptance.sh

# Run stage 7 acceptance with explicit configuration and summary path
./scripts/run_stage7_acceptance.sh --configuration debug --summary-json dist/stage7-summary.json

# Run distribution preflight against a bundle
./scripts/preflight_distribution.sh dist/MacWatch.app

# Run distribution preflight with explicit signing/notary inputs
./scripts/preflight_distribution.sh --identity "Developer ID Application: Team" --notary-profile "profile-name" dist/MacWatch.app
```

`./scripts/test.sh` runs `swift test` and then `./scripts/verify_stats_boundary.sh`. The boundary scan rejects forbidden Stats lifecycle, networking, updater, notification, widget, LevelDB, and SMC-write/helper patterns outside the allowed adapter boundary.

## Project architecture

MacWatch is a Swift Package for macOS 13+ focused on local Apple Silicon Mac temperature monitoring. It does not upload data and should not record user filenames, network contents, window titles, or process lists.

`Package.swift` defines these main targets:

- `MacWatchApp` executable depends on `MacWatchCore` and `StatsAdapter`. It owns the SwiftUI app, `AppDelegate`, menu bar entry, popup/dashboard/settings/detail/compatibility/first-run-guide views, runtime wiring, and acceptance CLI entry points.
- `MacWatchCore` library links `sqlite3` and owns domain logic: temperature models, probes protocol, reading validation, capabilities, sampling scheduler, `SampleBus`, live state, settings, lifecycle handling, SQLite-backed current-session history, trend queries, statistics, and downsampling.
- `StatsAdapter` library depends on `MacWatchCore` and `StatsAdapterIOHID`. It isolates read-only hardware collection for CPU, GPU, SSD/NAND, battery, system, and raw sensor temperatures.
- `StatsAdapterIOHID` is the minimal Objective-C HID sensors bridge linked to Foundation and IOKit.

Runtime flow is intentionally layered:

1. `StatsAdapter` creates read-only `TemperatureProbe` implementations. Fast probes currently cover CPU/GPU; slow probes cover SSD/NAND and battery; system and sensor probes are separated to avoid unnecessary high-frequency enumeration.
2. `MacWatchCore` validates samples, detects capability/status, schedules fast/slow sampling, emits sample/gap/capability events through `SampleBus`, and writes current-session history.
3. `MacWatchApp` builds `MacWatchRuntime`, observes live state/settings/history revisions, formats temperatures, and renders SwiftUI/menu bar UI.

Keep shared domain behavior in `MacWatchCore`, system collection in `StatsAdapter`, and presentation/runtime wiring in `MacWatchApp`.

## Current metrics and settings

Temperature metric names in current source:

- `cpu.temperature.hottest`, `cpu.temperature.average`
- `gpu.temperature.hottest`, `gpu.temperature.average`
- `ssd.temperature.internal`
- `battery.temperature`
- `system.temperature.hottest`
- `sensor.temperature.raw`

Current configurable settings:

- `launchMainWindowOnStart`
- `temperatureUnit`: `celsius` or `fahrenheit`
- `refreshInterval`: 5, 10, or 30 seconds
- `defaultTrendRange`
- `menuBarDisplayMetric`: hottest, CPU, GPU, SSD, or battery

`MenuBarDisplayMetric` decodes legacy raw value `memory` as `hottest`; memory temperature is not a current MVP metric.

## Acceptance and scripts

`MacWatchApp` supports:

- `--probe-temperature-once`
- `--acceptance-run <scenario>`

Supported acceptance scenarios:

- `probe-status`
- `dashboard-open`
- `popup-open`
- `trend-query`
- `sleep-wake-simulated`
- `first-run-guide`
- `launch-main-window-on-start-enabled`
- `launch-main-window-on-start-disabled`
- `resources-steady-state`

`./scripts/run_stage7_acceptance.sh` packages `dist/MacWatch.app` by default and aggregates probe, UI smoke, trend, lifecycle, resource, network, Stats boundary, and distribution preflight results into `dist/stage7-summary.json` unless `--summary-json` is supplied.

## Product and implementation boundaries

- MVP scope is temperature collection, capability detection, menu bar/popup/dashboard/details/settings/compatibility UI, first-run guide, current app-session history, and trend viewing.
- Do not add Post-MVP features unless explicitly requested: non-temperature resource monitoring, process statistics, alerts, export, cloud sync, remote monitoring, widgets, fan control, privileged helpers, or long-term cross-session history.
- Do not add memory temperature metrics unless explicitly requested and backed by the product/source documents.
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
