# Phase 7.6 手动测试步骤

这份文档用于手动验证 scanner parity cleanup。

## 1. 配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  removeGlobalFilter = true,
  queries = {
    all = "not done",
    by_heading = "not done\ngroup by heading",
  },
})
```

## 2. 准备文件

`Scanner.md`：

````markdown
# Work

- [ ] #task Visible #work

```text
- [ ] #task Hidden code
```

<!--
- [ ] #task Hidden html
-->

%%
- [ ] #task Hidden obsidian
%%

> [!todo] Callout
> - [ ] #task Callout task #callout

> - [ ] #task Quote task #quote

- [ ] #task2 Not included
````

## 3. 验证查询结果

运行：

```vim
:ObsidianTasks all
```

预期显示：

- `Visible #work`
- `Callout task #callout`
- `Quote task #quote`

预期不显示：

- `Hidden code`
- `Hidden html`
- `Hidden obsidian`
- `Not included`

并且显示文本中不再包含 `#task`，但仍保留 `#work`、`#callout`、`#quote`。

## 4. 验证 heading

运行：

```vim
:ObsidianTasks by_heading
```

预期这些任务归到 `Work` heading 下。

## 5. 验证 Lua 字段

运行：

```vim
:ObsidianTasksQuery filter by function task.is_blockquote == true
```

预期显示 callout task 和 quote task。

运行：

```vim
:ObsidianTasksQuery filter by function task.callout == "todo"
```

预期只显示 callout task。

## 6. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase7_6.sh
```

建议再跑：

```sh
sh scripts/smoke_phase7_5.sh
sh scripts/smoke_phase6_3.sh
sh scripts/smoke_phase6_8.sh
sh scripts/smoke_phase5.sh
```
