# Phase 7.8: Auto Refresh Result Buffers

目标：在 cache 已经能被保存、watcher、显式 API 更新后，让已打开的 Tasks result buffers 可以选择自动刷新，减少“cache 已经更新但结果页还要手动 `<C-r>`”的割裂感。

## 已实现

1. 新增 opt-in 配置：

```lua
require("obsidian-tasks").setup({
  cache = {
    enabled = true,
    auto_refresh_results = true,
    refresh_results_debounce_ms = 100,
  },
})
```

兼容 camelCase：

```lua
cache = {
  enabled = true,
  autoRefreshResults = true,
  refreshResultsDebounceMs = 100,
}
```

也兼容语义化别名：

```lua
cache = {
  enabled = true,
  refresh_results_on_update = true,
}
```

2. 新增 `display.refresh_all_task_views(opts)`：
   - 遍历所有仍有效的 Tasks result buffers。
   - 复用每个 buffer 自己保存的 finder/query opts。
   - 跳过有未保存修改的 result buffer。
   - 刷新后恢复原当前窗口和当前 buffer，避免自动刷新抢焦点。
   - 返回 `{ refreshed, skipped_modified, skipped_invalid }`。
3. 新增 `cache.refresh_result_buffers(opts)`，作为 cache 到 display 的薄封装。
4. `cache.update_file()` / `cache.remove_file()` 更新 warm cache 后：
   - 如果 `auto_refresh_results = true`，会刷新所有 result buffers。
   - 如果设置 `refresh_results_debounce_ms`，会合并短时间内多次 cache update。
5. `cache.stats()` 暴露：
   - `auto_refresh_results`
   - `pending_result_refresh`

## 行为边界

- 默认关闭。需要显式配置 `cache.auto_refresh_results = true`。
- 未保存的 result buffer 不会被自动覆盖；用户仍需先保存或放弃本地编辑。
- 自动刷新只重跑已打开 result buffer 原本的 query，不会创建新 result buffer。
- cache cold 时单文件事件仍不会触发 full refresh，因此也不会自动刷新结果。
- 自动刷新依赖已打开 result buffer 保存过 finder opts；普通 Markdown buffer 不受影响。

## 验证

自动 smoke：

```sh
sh scripts/smoke_phase7_8.sh
```

建议回归：

```sh
sh scripts/smoke_phase7_2.sh
sh scripts/smoke_phase7_3.sh
sh scripts/smoke_phase7_4.sh
sh scripts/smoke_phase7_7.sh
```
