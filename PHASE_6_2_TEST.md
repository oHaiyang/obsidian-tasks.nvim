# Phase 6.2 手动测试步骤

这份文档用于手动验证 urgency score、urgency sorting/grouping 和 `show urgency`。

## 1. 准备测试 vault

创建测试文件：

````markdown
# Urgency

```tasks
not done
sort by urgency
show urgency
```

```tasks
not done
sort by urgency reverse
show urgency
```

```tasks
not done
group by urgency
show urgency
```

- [ ] #task Highest due today 🔺 📅 2026-05-16
- [ ] #task Medium due today 🔼 📅 2026-05-16
- [ ] #task High scheduled started ⏫ 🛫 2026-05-15 ⏳ 2026-05-15
- [ ] #task Low future 🔽 📅 2026-06-16
- [ ] #task Normal no date
- [ ] #task Lowest no date ⏬
````

## 2. 临时加载插件

在 `obsidian-tasks.nvim` 目录启动：

```sh
nvim -u NONE \
  --cmd 'set rtp+=.' \
  --cmd 'runtime plugin/obsidian-tasks.lua' \
  /tmp/obsidian-tasks-phase6-2/Urgency.md
```

进入 Neovim 后执行：

```vim
:lua require("obsidian-tasks").setup({ vault_path = "/tmp/obsidian-tasks-phase6-2", global_filter = "#task", today = "2026-05-16", enable_lua_filters = true })
```

## 3. 测试 show urgency

建议配置 named query 后执行 `:ObsidianTasks <name>`。也可以执行 `:ObsidianTasksQuery` 后在 prompt 中输入多行 query。

预期：

- 每条任务显示 `urgency NN.NN`。
- `Highest due today` 显示约 `17.80`。
- `Medium due today` 显示约 `12.70`。
- `Normal no date` 显示 `1.95`。
- `Lowest no date` 显示 `-1.80`。

## 4. 测试排序

使用：

```tasks
not done
sort by urgency
show urgency
```

预期高分在前：

1. `Highest due today`
2. `Medium due today`
3. `High scheduled started`
4. `Low future`
5. `Normal no date`
6. `Lowest no date`

使用：

```tasks
not done
sort by urgency reverse
show urgency
```

预期低分在前。

## 5. 测试分组

使用：

```tasks
not done
group by urgency
show urgency
```

预期分组 heading 是两位小数，并且从高分到低分。

## 6. 测试 function filter

使用：

```tasks
filter by function task.urgency > 10
sort by urgency
show urgency
```

预期只显示 urgency 大于 `10` 的任务。

## 7. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase6_2.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase5.sh
sh scripts/smoke_phase4.sh
```
