# Phase 4: Status Semantics + Editing Actions

目标：把 Phase 1 的简单 checkbox toggle 升级为接近 Obsidian Tasks 的 status-aware editing：自定义状态、完成/取消日期、递归任务完成、依赖查询和 postpone。

Phase 4 只实现原 Obsidian Tasks 已有的能力，不引入新的任务模型。Neovim 侧的差异主要在交互形式：Obsidian 用按钮、右键菜单和命令面板；本插件用 user command、结果 buffer keymap 和 Lua API。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_4_TEST.md`，headless smoke 见 `scripts/smoke_phase4.sh`。

已覆盖：

- `status.lua`：status registry，支持 `symbol/name/type/next_symbol`。
- `mutation.lua`：统一处理状态变更、done/cancelled date、recurrence writeback、postpone。
- `recurrence.lua`：完成 recurring task 后生成下一次任务。
- `dependencies.lua`：`is blocked` / `is blocking` 查询。
- 命令：
  - `:ObsidianTasksToggle`
  - `:ObsidianTasksChangeStatus {status}`
  - `:ObsidianTasksStatusDone` / `:ObsidianTasksStatusTodo` / `:ObsidianTasksStatusInProgress` / `:ObsidianTasksStatusCancelled`
  - `:ObsidianTasksPostpone [date]`
- 结果 buffer keymap：
  - `<space>` toggle
  - `s` 选择 status
  - `p` postpone

仍留到后续打磨：

- recurrence rule 目前覆盖 `every day/week/month/year`、`every N days/weeks/months/years`、`every other ...`，还不是原插件完整 parser。
- postpone 目前支持默认 next day、`YYYY-MM-DD`、`today/tomorrow/yesterday`、`+N`、`N days`，还没有完整自然语言日期。
- 编辑 modal、日期 picker、dependency editor 暂未实现。

## 配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",

  status_settings = {
    { symbol = " ", name = "Todo",        type = "TODO",        next_symbol = "x" },
    { symbol = "x", name = "Done",        type = "DONE",        next_symbol = " " },
    { symbol = "/", name = "In Progress", type = "IN_PROGRESS", next_symbol = "x" },
    { symbol = "-", name = "Cancelled",   type = "CANCELLED",   next_symbol = " " },
  },

  set_done_date = true,
  set_cancelled_date = true,
  set_created_date = false,
  recurrence_on_next_line = false,
  remove_scheduled_date_on_recurrence = false,
})
```

兼容 camelCase：

- `statusSettings`
- `setDoneDate`
- `setCancelledDate`
- `setCreatedDate`
- `recurrenceOnNextLine`
- `removeScheduledDateOnRecurrence`

## 查询语法新增

Status：

```tasks
done
not done
status is x
status is Done
status.type is DONE
status.type is not CANCELLED
status.name includes Progress
```

Dependencies：

```tasks
has id
no id
has depends on
no depends on
is blocked
is not blocked
is blocking
is not blocking
```

`done` / `not done` 现在按 status type 判断：`DONE`、`CANCELLED`、`NON_TASK` 视为 complete，其余视为 incomplete。

## 编辑行为

### Toggle

`<space>` 或 `:ObsidianTasksToggle` 会按当前 status 的 `next_symbol` 切换。

例：

```markdown
- [ ] Todo
- [/] In progress
- [x] Done
```

默认 registry 下：

- `[ ]` -> `[x]`
- `[/]` -> `[x]`
- `[x]` -> `[ ]`
- `[-]` -> `[ ]`

### Change Status

```vim
:ObsidianTasksChangeStatus Done
:ObsidianTasksChangeStatus IN_PROGRESS
:ObsidianTasksChangeStatus /
:ObsidianTasksStatusDone
```

在普通 Markdown buffer 中执行会直接修改当前任务行。

在 Tasks result buffer 中执行只修改结果行，需要 `<c-s>` 或 `:write` 保存回源文件，这和 Phase 1/2 的结果 buffer 编辑模型一致。

### Done / Cancelled Date

当 `set_done_date = true`：

```markdown
- [ ] Ship feature
```

切到 DONE 后：

```markdown
- [x] Ship feature ✅ 2026-05-15
```

从 DONE 切回 incomplete status 会移除 `✅ YYYY-MM-DD`。

当 `set_cancelled_date = true`：

```markdown
- [-] Drop old idea ❌ 2026-05-15
```

从 CANCELLED 切回 incomplete status 会移除 `❌ YYYY-MM-DD`。

### Recurring Completion

完成 recurring task 时生成下一次任务：

```markdown
- [ ] Daily review 🔁 every day 📅 2026-05-15
```

完成后，如果 `recurrence_on_next_line = true`：

```markdown
- [x] Daily review 🔁 every day 📅 2026-05-15 ✅ 2026-05-15
- [ ] Daily review 🔁 every day 📅 2026-05-16
```

如果 `recurrence_on_next_line = false`，下一次任务插在完成任务上方。

当前 recurrence MVP 会在新任务中移除 `✅`、`❌`、`🆔`、`⛔`。如果 `set_created_date = true`，新任务会写入 `➕ today`。

### Postpone

```vim
:ObsidianTasksPostpone
:ObsidianTasksPostpone tomorrow
:ObsidianTasksPostpone 2026-05-20
:ObsidianTasksPostpone +3
```

Postpone 按 Obsidian Tasks 的顺序选择第一个存在日期：

1. due date
2. scheduled date
3. start date

不带参数时：

- 过期或今天的任务推迟到明天。
- 未来任务向后推一天。

在 result buffer 中执行会立即写回源文件并刷新当前结果。

## Phase 4 验收

- 自定义 status registry 可以影响 toggle、done/not done 查询和 status command。
- `DONE` / `CANCELLED` 日期能按设置自动增删。
- recurring task 完成后能生成下一次任务。
- `is blocked` / `is blocking` 只把 incomplete dependency 视为 blocker。
- `:ObsidianTasksPostpone` 能修改 due/scheduled/start 中优先级最高的日期。
- Phase 2/3 smoke 无回归。
