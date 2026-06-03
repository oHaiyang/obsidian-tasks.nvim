# Phase 7.1 手动测试步骤

这份文档用于手动验证 Vault Cache API MVP。

## 1. 配置

在测试 vault 中配置：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  cache = {
    enabled = true,
  },
  queries = {
    all = "not done",
  },
})
```

准备两个文件。

`A.md`：

```markdown
# A

- [ ] #task Alpha
```

`B.md`：

```markdown
# B

- [ ] #task Beta
```

## 2. 初次 warm cache

运行：

```vim
:ObsidianTasksRefreshCache
:ObsidianTasksCacheInfo
```

预期：

- cache 状态为 warm。
- file count 至少为 2。
- task count 为 2。

## 3. 查询走 cache

运行：

```vim
:ObsidianTasks all
```

预期显示 Alpha 和 Beta。

## 4. 验证 cache 暂不自动更新

把 `A.md` 改成：

```markdown
# A

- [ ] #task Alpha
- [ ] #task Gamma
```

保存后再次运行：

```vim
:ObsidianTasks all
```

Phase 7.1 预期仍只显示 Alpha 和 Beta，因为自动 `BufWritePost` update 留到 Phase 7.2。

## 5. 手动刷新单文件

运行：

```vim
:lua require("obsidian-tasks.cache").update_file(vim.fn.expand("%:p"))
```

或全量刷新：

```vim
:ObsidianTasksRefreshCache
```

再运行：

```vim
:ObsidianTasks all
```

预期显示 Alpha、Gamma、Beta。

## 6. 清空 cache

运行：

```vim
:ObsidianTasksClearCache
:ObsidianTasksCacheInfo
```

预期 cache 状态回到 cold，file/task count 为 0。

再次运行：

```vim
:ObsidianTasks all
```

预期会重新 warm cache 并显示当前任务。

## 7. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase7_1.sh
```

建议再跑：

```sh
sh scripts/smoke_phase6_8.sh
sh scripts/smoke_phase6_7.sh
sh scripts/smoke_phase5_10.sh
sh scripts/smoke_phase5.sh
```
