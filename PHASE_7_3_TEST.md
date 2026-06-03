# Phase 7.3 手动测试步骤

这份文档用于手动验证 result refresh 和 cache 的集成。

## 1. 配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  cache = {
    enabled = true,
    auto_update_on_write = true,
  },
  queries = {
    all = "not done",
    beta = "description includes Beta",
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

- [ ] #task Beta
```

## 3. Warm cache 并打开两个 result

```vim
:ObsidianTasksRefreshCache
:ObsidianTasks all
:ObsidianTasks! beta
```

预期：

- active result 显示 Alpha 和 Beta。
- pinned result 只显示 Beta。

## 4. 验证 result refresh 不会串 query

在 `A.md` 增加：

```markdown
- [ ] #task Gamma
```

保存后回到 active result：

```vim
:ObsidianTasksRefresh
```

预期 active result 显示 Alpha、Gamma、Beta。

切到 pinned `beta` result：

```vim
:ObsidianTasksRefresh
```

预期仍只显示 Beta，不显示 Alpha/Gamma。

## 5. 验证显式 cache + result refresh

如果用外部工具修改了 vault 文件，普通 result refresh 只会读取当前 cache。此时可在 result buffer 中运行：

```vim
:ObsidianTasksRefreshCache!
```

预期：

- 先全量刷新 cache。
- 再刷新当前 result buffer。

## 6. 验证未保存 result buffer 不被覆盖

在 result buffer 中手动改一行但不要保存，然后运行：

```vim
:ObsidianTasksRefresh
```

预期提示需要先保存 task changes，当前手动修改不会被刷新覆盖。

## 7. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase7_3.sh
```

建议再跑：

```sh
sh scripts/smoke_phase7_2.sh
sh scripts/smoke_phase7_1.sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase5.sh
```
