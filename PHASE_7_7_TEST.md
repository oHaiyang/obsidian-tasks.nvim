# Phase 7.7 手动测试步骤

目标：确认 weekday/monthday recurrence 在真实 Neovim 里完成任务时能生成正确的下一条任务。

## 1. 准备测试 vault

创建一个临时 Markdown 文件，例如：

```markdown
# Phase 7.7

- [ ] #task Weekday 🔁 every weekday 📅 2026-06-05
- [ ] #task Monday 🔁 every monday 📅 2026-06-01
- [ ] #task Biweekly Friday 🔁 every 2 weeks on friday 📅 2026-06-05
- [ ] #task Monthday 🔁 every month on the 15th 📅 2026-06-10
- [ ] #task Done based 🔁 every weekday when done 📅 2026-06-01
```

推荐临时配置：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/test-vault",
  global_filter = "#task",
  set_done_date = true,
  recurrence_on_next_line = true,
})
```

## 2. 完成 weekday 任务

把光标放到：

```markdown
- [ ] #task Weekday 🔁 every weekday 📅 2026-06-05
```

执行：

```vim
:ObsidianTasksStatusDone
```

预期生成：

```markdown
- [x] #task Weekday 🔁 every weekday 📅 2026-06-05 ✅ <today>
- [ ] #task Weekday 🔁 every weekday 📅 2026-06-08
```

`2026-06-05` 是周五，下一次 weekday 应是 `2026-06-08` 周一。

## 3. 完成指定 weekday 任务

把光标放到：

```markdown
- [ ] #task Monday 🔁 every monday 📅 2026-06-01
```

执行 `:ObsidianTasksStatusDone`。

预期下一条 due date 为：

```markdown
📅 2026-06-08
```

同一天命中 Monday 时，会推进到下一周 Monday。

## 4. 完成隔周 weekday 任务

把光标放到：

```markdown
- [ ] #task Biweekly Friday 🔁 every 2 weeks on friday 📅 2026-06-05
```

执行 `:ObsidianTasksStatusDone`。

预期下一条 due date 为：

```markdown
📅 2026-06-19
```

## 5. 完成 monthday 任务

把光标放到：

```markdown
- [ ] #task Monthday 🔁 every month on the 15th 📅 2026-06-10
```

执行 `:ObsidianTasksStatusDone`。

预期下一条 due date 为：

```markdown
📅 2026-06-15
```

如果当前 due date 已经过了当月 15 号，例如 `2026-06-20`，下一条应变成 `2026-07-15`。

## 6. 验证 when done

把光标放到：

```markdown
- [ ] #task Done based 🔁 every weekday when done 📅 2026-06-01
```

在真实手测里，下一次会根据当天日期计算，而不是根据旧 due date 计算。

如果今天是周五，下一次应是下周一；如果今天是周一到周四，下一次应是明天；如果今天是周六或周日，下一次应是下周一。

## 7. 自动 smoke

在插件目录执行：

```sh
sh scripts/smoke_phase7_7.sh
```

建议一并跑回归：

```sh
sh scripts/smoke_phase4.sh
sh scripts/smoke_phase6_7.sh
sh scripts/smoke_phase7_6.sh
```
