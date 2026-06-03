# Phase 6.7 手动测试步骤

这份文档用于手动验证 Dataview task format MVP。

## 1. 配置

在本地插件配置中启用 Dataview format：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  task_format = "dataview",
  set_done_date = true,
  set_cancelled_date = true,
})
```

## 2. 准备任务

新建 `Dataview Test.md`：

```markdown
- [ ] #task High dataview  [priority:: high]  [due:: 2026-05-20]  [id:: alpha-id]
- [ ] #task Beta target  [id:: beta-id]
- [ ] #task Current depends  [dependsOn:: alpha-id]
- [ ] #task Form source  [due:: 2026-05-20]
- [ ] #task Recurring source  [repeat:: every week]  [due:: 2026-05-20]  [id:: recur-id]  [dependsOn:: alpha-id]
```

## 3. 查询 Dataview 字段

运行：

```vim
:ObsidianTasksQuery not done
  due before 2026-05-22
  priority is high
  has id
```

预期只显示：

```markdown
- [ ] #task High dataview ...
```

## 4. Toggle done 写 completion

把光标放到第一条任务上，执行：

```vim
:ObsidianTasksToggle
```

预期：

- checkbox 变为 `[x]`。
- 行尾写入 `[completion:: YYYY-MM-DD]`。
- 不出现 `✅ YYYY-MM-DD`。

## 5. Date picker 写 Dataview date

把光标放到 `Form source` 行：

```vim
:ObsidianTasksPickDate! due
```

选择一个日期后按 `<CR>`。

预期：

- 更新 `[due:: YYYY-MM-DD]`。
- 不出现 `📅 YYYY-MM-DD`。

再执行同一个命令，按 `c` 清空。

预期 `[due:: ...]` 被移除。

## 6. Dependency editor 写 dependsOn

把光标放到 `Current depends` 行：

```vim
:ObsidianTasksAddDependency
```

选择 `Beta target`。

预期当前任务写成类似：

```markdown
[dependsOn:: alpha-id, beta-id]
```

不应该出现 `⛔ beta-id`。

## 7. Edit form 保存 Dataview fields

把光标放到 `Form source` 行：

```vim
:ObsidianTasksEdit
```

在 form 中设置：

```text
priority: high
due: tomorrow
id: form-id
depends_on: beta-id
```

保存：

```vim
<C-S>
```

预期源任务行包含：

```markdown
[priority:: high]
[due:: YYYY-MM-DD]
[id:: form-id]
[dependsOn:: beta-id]
```

并且不包含 priority/date/dependency emoji。

## 8. Dataview completion

在普通 task 行输入：

```markdown
- [ ] #task Priority h
```

触发补全，预期候选包含：

```text
[priority:: high]
```

在未闭合 inline field 中输入：

```markdown
- [ ] #task Due [due:: tom
```

触发补全，预期候选包含 ISO date。

在依赖字段中输入：

```markdown
- [ ] #task Current [id:: current-id] [dependsOn:: b
```

触发补全，预期可补 `beta-id`，但不推荐 `current-id`。

## 9. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase6_7.sh
```

建议再跑：

```sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase5_5.sh
sh scripts/smoke_phase4.sh
sh scripts/smoke_phase5.sh
sh scripts/smoke_phase6_native_completion.sh
```
