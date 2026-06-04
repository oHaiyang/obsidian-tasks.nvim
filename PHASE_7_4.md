# Phase 7.4: File Watcher + Debounce

目标：在 Phase 7.1 到 7.3 的 cache-first 基础上，让 cache 能感知 vault 内 Markdown 文件被外部程序创建、修改或删除的情况。

## 已实现

1. 新增 opt-in vault watcher：

```lua
require("obsidian-tasks").setup({
  cache = {
    enabled = true,
    watch = true,
    watch_debounce_ms = 100,
  },
})
```

兼容写法：

```lua
cache = {
  enabled = true,
  watch_vault = true,
  watchDebounceMs = 100,
}
```

以及：

```lua
cache = {
  enabled = true,
  watcher = {
    enabled = true,
    debounce_ms = 100,
  },
}
```

2. 新增 cache API：
   - `cache.start_watcher(config)`
   - `cache.stop_watcher()`
   - `cache.on_fs_event(filename, events, opts)`
3. 新增用户命令：
   - `:ObsidianTasksStartCacheWatcher`
   - `:ObsidianTasksStopCacheWatcher`
4. `:ObsidianTasksCacheInfo` 会显示 watcher 状态：
   - `running`
   - `stopped`
   - `unavailable`
   - `error`
5. watcher 收到 `.md` 文件事件后：
   - 文件存在时调用 `cache.update_file(path, { refresh_if_cold = false })`。
   - 文件不存在时从 warm cache 移除对应 file entry。
   - 非 Markdown 文件和 vault 外路径会被忽略。
6. 支持 debounce：
   - `cache.watch_debounce_ms`
   - `cache.watchDebounceMs`
   - `cache.watcher.debounce_ms`
   - `cache.watcher.debounceMs`
   - 未设置时回退到 `cache.debounce_ms`。

## 行为边界

- watcher 默认关闭，需要显式 `cache.watch = true`。
- watcher 依赖 Neovim/libuv 的 `fs_event`。如果当前系统或路径不支持，会把状态设为 `unavailable`，不影响手动 refresh、BufWritePost 更新或普通查询。
- Phase 7.4 不会在 cache cold 时因为单个文件事件触发全 vault refresh；这和 Phase 7.2 的 `BufWritePost` 语义一致。
- 文件 rename 在 libuv 里通常表现为旧路径 delete + 新路径 create。只要系统送达对应 `.md` 事件，cache 会移除旧文件并扫描新文件。
- 自动刷新已打开 result buffer 仍不默认开启。文件事件只更新 cache；用户继续用 `<C-r>` / `:ObsidianTasksRefresh` / `:ObsidianTasksRefreshCache!` 刷新结果视图。

## 验证

自动 smoke：

```sh
sh scripts/smoke_phase7_4.sh
```

建议回归：

```sh
sh scripts/smoke_phase7_1.sh
sh scripts/smoke_phase7_2.sh
sh scripts/smoke_phase7_3.sh
sh scripts/smoke_phase7_6.sh
```
