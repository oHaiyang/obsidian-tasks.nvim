# Phase 7.1: Vault Cache API MVP

目标：新增一个可控启用的 vault task cache，让查询、preview、dependency search 和 completion 可以共享同一份任务索引。

## 已实现

- 新增 `lua/obsidian-tasks/cache.lua`。
- `setup()` 支持：

```lua
require("obsidian-tasks").setup({
  cache = {
    enabled = true,
  },
})
```

兼容别名：

```lua
cache = true
cache_enabled = true
cacheEnabled = true
```

- 新增 cache API：
  - `require("obsidian-tasks.cache").refresh(opts)`
  - `require("obsidian-tasks.cache").tasks(opts)`
  - `require("obsidian-tasks.cache").update_file(path, opts)`
  - `require("obsidian-tasks.cache").remove_file(path)`
  - `require("obsidian-tasks.cache").clear()`
  - `require("obsidian-tasks.cache").stats()`
- `require("obsidian-tasks")` re-export：
  - `refresh_cache(opts)`
  - `clear_cache()`
  - `cache_stats()`
- 新增用户命令：
  - `:ObsidianTasksRefreshCache`
  - `:ObsidianTasksClearCache`
  - `:ObsidianTasksCacheInfo`
- 接入调用方：
  - `finder.find_tasks()` / `:ObsidianTasks`
  - inline preview
  - dependency search
  - completion existing ids

## Cache Context

Cache 会按以下 context 区分：

- `vault_path`
- `global_filter`
- `today`
- `task_format`

如果这些值变化，下一次 `cache.tasks()` 会自动重新 warm cache。

## 行为边界

- 默认仍不强制启用 cache，避免改变已有用户的“实时全量扫描”预期。
- 启用 cache 后，文件变化不会在 Phase 7.1 自动进入 cache。
- 手动更新方式：
  - 全量：`:ObsidianTasksRefreshCache`
  - 单文件 Lua API：`require("obsidian-tasks.cache").update_file(path)`
  - 清空：`:ObsidianTasksClearCache`
- Phase 7.2 会补 `BufWritePost` 单文件自动 update。

## 示例

```lua
require("obsidian-tasks").setup({
  vault_path = vim.fn.expand("~/Vault"),
  global_filter = "#task",
  cache = {
    enabled = true,
  },
})
```

手动刷新：

```vim
:ObsidianTasksRefreshCache
```

查看状态：

```vim
:ObsidianTasksCacheInfo
```

Lua 调试：

```lua
local cache = require("obsidian-tasks.cache")
cache.refresh()
vim.print(cache.stats())
```

## 验收

- cache disabled 时，`cache.tasks()` 仍走旧 scanner 路径。
- cache enabled 时，第一次查询 warm cache，后续查询复用结果。
- `cache.update_file(path)` 只重扫单个文件并重建 task array。
- `cache.clear()` 后下一次 cache 查询会重新 warm。
- `:ObsidianTasks` 和 preview 不需要知道 cache 细节。

## 自动测试

```sh
sh scripts/smoke_phase7_1.sh
```

建议回归：

```sh
sh scripts/smoke_phase6_8.sh
sh scripts/smoke_phase6_7.sh
sh scripts/smoke_phase5_10.sh
sh scripts/smoke_phase5.sh
```
