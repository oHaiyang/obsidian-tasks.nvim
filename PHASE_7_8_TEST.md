# Phase 7.8 手动测试步骤

目标：确认 cache 更新后，已打开的 Tasks result buffers 可以自动刷新，并且不会覆盖未保存修改。

## 1. 启用配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/test-vault",
  global_filter = "#task",
  cache = {
    enabled = true,
    auto_update_on_write = true,
    auto_refresh_results = true,
    refresh_results_debounce_ms = 100,
  },
})
```

如果你也在测试 watcher：

```lua
cache = {
  enabled = true,
  watch = true,
  auto_refresh_results = true,
}
```

## 2. 打开 result buffer

执行：

```vim
:ObsidianTasksRefreshCache
:ObsidianTasks
```

或打开某个命名 query：

```vim
:ObsidianTasksQuery all
```

确认 result buffer 中能看到已有任务。

## 3. 修改源文件并保存

在 vault 内某个 Markdown 文件添加：

```markdown
- [ ] #task Auto refresh visible
```

保存文件。

回到 result buffer，预期无需 `<C-r>`，该任务会在 debounce 后出现。

## 4. 多 result buffers

打开两个不同 query，其中一个 pinned：

```vim
:ObsidianTasksQuery all
:ObsidianTasksQuery! today
```

修改源文件并保存。

预期两个 result buffers 都按自己的 query 刷新，不会互相串 query。

## 5. 未保存 result buffer

在 result buffer 里手动加一行临时文字，让 buffer 变成 modified。

再修改源文件并保存。

预期：

- modified result buffer 不会被自动覆盖。
- 保存或放弃修改后，再执行 `<C-r>` 可以手动刷新。

## 6. 自动 smoke

在插件目录执行：

```sh
sh scripts/smoke_phase7_8.sh
```
