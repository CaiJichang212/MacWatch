Stats复用策略

## 索引目录（大模型检索用）

> 使用方式：先按本索引定位需要章节，再只读取对应片段，避免把整篇文档塞入上下文。

- 推荐策略：确认采用“MacWatch 独立仓库 + Stats 只读 Git submodule + 自写 Adapter 层”的总体取舍。
- 当前仓库结构：查看 `Sources/MacWatchApp`、`Sources/MacWatchCore`、`Sources/StatsAdapter`、`Vendor/Stats`、`patches/stats` 的职责。
- 开发规则：确认 `Vendor/Stats` 只读、只通过 `StatsAdapter` 包装、禁止依赖 Stats UI/Remote/LevelDB、固定 tag/commit 和升级流程。
- 不建议的方案：判断为什么不 fork Stats、不复制 Stats 源码、不提前改 Stats。
- 例外处理：查找必须微调 Stats 文件时优先使用 Adapter、target 配置、patch 或 fork 的顺序。

建议用这个策略：**MacWatch 独立仓库 + Stats 作为只读 Git submodule + 自己写 Adapter 层**。

原因很直接：Stats 是完整 macOS App，不是稳定的 Swift Package “第三方库”。它有 App、Modules、Kit、SMC、Widgets 等完整工程结构；直接当 SPM 依赖调用大概率不现实。把它作为**源码级上游依赖**固定到某个 release/tag，然后在 MacWatch 里只引用需要的采集代码或参考实现。

**当前仓库结构**
```text
MacWatch/
  docs/
  MacWatch.xcodeproj 或 Package.swift
  Sources/
    MacWatchApp/
    MacWatchCore/
    StatsAdapter/        # 只放你自己的适配代码
  Vendor/
    Stats/               # git submodule，只读，不改
  patches/
    stats/               # 万不得已才放补丁
```

当前项目已经初始化并配置Stats的 Git submodule，版本为 `v3.0.1`。

**开发规则**
1. `Vendor/Stats/` 目录默认只读，不在里面提交 MacWatch 业务代码。
2. MacWatch 只通过 `StatsAdapter` 调用或包装 Stats 的采集能力。
3. 不依赖 Stats 的 UI、Remote、LevelDB 历史存储；长期记录、告警、趋势分析放在 MacWatch 自己的 Core/Storage 里。
4. 固定到 tag 或 commit，不跟随 `master`。
5. 每次升级 Stats 单独开分支，例如：
```bash
git switch -c chore/update-stats-v3.0.2
git -C Vendor/Stats fetch --tags
git -C Vendor/Stats checkout v3.0.2
git add Vendor/Stats
git commit -m "chore: update Stats to v3.0.2"
```

**不建议的方案**
- 不建议直接 fork Stats 然后把 MacWatch 写进去：后面会和上游 Stats 更新混在一起，维护成本高。
- 不建议复制 Stats 源码到 MacWatch：短期简单，长期无法清楚追踪上游变更。
- 不建议一开始就改 Stats：你的目标是“复用采集能力 + 新增历史分析”，应把产品能力沉到 MacWatch 自己的架构里。

如果后面发现某些 Stats 文件必须微调才能编译进 MacWatch，优先做成 `StatsAdapter` 或 Xcode target 配置；
实在需要改源码，再考虑 fork 或 `patches/stats/*.patch`，但那应该是例外。