# Phase 7.3: Result Refresh Integration

目标：让 result buffer 刷新路径和 Phase 7 cache 明确集成，避免 active/pinned 多查询结果互相污染刷新上下文。

## 已实现

- `display.refresh_tasks_view(opts)` 支持：
  - `opts.buffer` / `opts.buf` 指定要刷新的 result buffer。
  - 只使用该 buffer 保存的 `buffer_finder_opts` 重跑查询。
  - 不再从当前 buffer 内容猜测 grouping/layout。
  - 未保存的 result buffer 会拒绝刷新，避免覆盖用户手动编辑。
  - 刷新后尽量恢复 cursor。
- `<C-r>` 映射固定刷新当前 result buffer。
- 新增命令：

```vim
:ObsidianTasksRefresh
```

- `:ObsidianTasksRefreshCache` 支持 bang：

```vim
:ObsidianTasksRefreshCache!
```

带 bang 时会在刷新 cache 后刷新当前 result buffer；不带 bang 仍只刷新 cache。

## Cache 关系

- cache enabled 且 warm 时，result refresh 通过 finder 读取 cache。
- result refresh 本身不做 full cache refresh。
- 如果 cache stale，`<C-r>` 会忠实显示 stale cache；需要依靠 Phase 7.2 的 `BufWritePost`、显式 `cache.update_file()` 或 `:ObsidianTasksRefreshCache` 更新 cache。
- `:ObsidianTasksRefreshCache!` 是“先全量刷新 cache，再刷新当前 result”的显式组合操作。

## 当前边界

- cache update 后不会自动刷新所有已打开 result buffer。
- Phase 7.3 只提供当前 result buffer 的刷新集成；后台批量刷新 active/pinned buffers 留到后续确有需要时做。
- 如果当前 buffer 不是 Tasks result buffer，`:ObsidianTasksRefreshCache!` 只刷新 cache，不强行打开或刷新结果。

## 验收

- `<C-r>` / `:ObsidianTasksRefresh` 能复用当前 result buffer 的原 query。
- active result 和 pinned result 分别刷新时不会串 query。
- cache stale 时刷新 result 不会偷偷 full scan。
- `:ObsidianTasksRefreshCache!` 能显式刷新 cache 并刷新当前 result。
- 未保存的 result buffer 刷新会被拒绝。

## 自动测试

```sh
sh scripts/smoke_phase7_3.sh
```

建议回归：

```sh
sh scripts/smoke_phase7_2.sh
sh scripts/smoke_phase7_1.sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase5.sh
```
