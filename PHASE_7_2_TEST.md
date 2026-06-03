# Phase 7.2 手动测试步骤

这份文档用于手动验证 `BufWritePost` 单文件 cache update。

## 1. 配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  cache = {
    enabled = true,
    auto_update_on_write = true,
    debounce_ms = 0,
  },
  queries = {
    all = "not done",
  },
})
```

## 2. 准备文件

`A.md`：

```markdown
# A

- [ ] #task Alpha
```

`B.md`：

```markdown
# B

- [ ] #task Beta 📅 2026-06-03
```

## 3. Warm cache

运行：

```vim
:ObsidianTasksRefreshCache
:ObsidianTasks all
```

预期显示 Alpha 和 Beta。

## 4. 保存后自动更新单文件 cache

打开 `A.md`，新增：

```markdown
- [ ] #task Gamma
```

保存：

```vim
:write
```

不运行 `:ObsidianTasksRefreshCache`，直接刷新 query result：

```vim
:ObsidianTasks all
```

预期显示 Alpha、Gamma、Beta。

## 5. Cache cold 时不自动 full refresh

运行：

```vim
:ObsidianTasksClearCache
```

再次编辑并保存 `A.md`。然后：

```vim
:ObsidianTasksCacheInfo
```

预期 cache 仍是 cold。下一次运行 query 时才会 warm cache。

## 6. 直接写文件 mutation 路径

在 result buffer 中对 Beta 执行 postpone，例如：

```vim
:ObsidianTasksPostpone +1
```

或使用插件内其它会直接写源文件的动作。

预期无需手动 refresh cache，重新运行 query 后 Beta 的日期信息来自更新后的 cache。

## 7. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase7_2.sh
```

建议再跑：

```sh
sh scripts/smoke_phase7_1.sh
sh scripts/smoke_phase6_8.sh
sh scripts/smoke_phase5.sh
```
