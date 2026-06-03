# Phase 7.2: BufWritePost Single-file Cache Update

目标：在 Phase 7.1 的 opt-in vault cache 基础上，让 cache enabled 用户保存 Markdown 文件后自动更新该文件的 task cache。

## 已实现

- `setup()` 会调用 `require("obsidian-tasks.cache").setup(config)`。
- cache enabled 时注册 `ObsidianTasksCache` augroup：
  - `BufWritePost *.md`
  - 只处理 `vault_path` 内的 Markdown 文件。
  - 只在 cache 已 warm 且 context 匹配时更新单文件，避免首次保存触发全 vault refresh。
- 配置：

```lua
require("obsidian-tasks").setup({
  cache = {
    enabled = true,
    auto_update_on_write = true,
    debounce_ms = 0,
  },
})
```

兼容 camelCase：

```lua
cache = {
  enabled = true,
  autoUpdateOnWrite = true,
  debounceMs = 100,
}
```

- 新增/扩展 cache API：
  - `cache.setup(config)`
  - `cache.on_buf_write(path, opts)`
  - `cache.on_file_changed(path, opts)`
  - `cache.is_path_in_vault(path, vault_path)`
  - `cache.update_file(path, { refresh_if_cold = false })`
- 直接写源文件的路径会显式通知 cache：
  - result buffer save status changes。
  - result buffer postpone。
  - dependency editor 为目标任务补 `id`。
  - edit form 写入未加载文件。

## 行为边界

- Source buffer 中未保存的修改不会进入 cache；cache 代表磁盘上的 vault 状态。
- 如果 cache 仍是 cold，`BufWritePost` 不会自动 full refresh。
- 删除/重命名仍不做自动 watcher，留给 Phase 7.4。
- 已打开 result buffer 不会因为 cache update 自动重绘；仍通过 `<C-r>` 或重新运行 query 刷新，结果刷新集成留给 Phase 7.3。

## 验收

- cache warm 后，保存 vault 内 `.md` 文件会重扫该文件。
- 保存 vault 外文件不会影响 cache。
- cache cold 时保存文件不触发全 vault refresh。
- 直接 `io.open(..., "w")` 写源文件的 mutation 路径会更新 cache。
- cache disabled 或 `auto_update_on_write = false` 时不注册有效自动更新。

## 自动测试

```sh
sh scripts/smoke_phase7_2.sh
```

建议回归：

```sh
sh scripts/smoke_phase7_1.sh
sh scripts/smoke_phase6_8.sh
sh scripts/smoke_phase5.sh
```
