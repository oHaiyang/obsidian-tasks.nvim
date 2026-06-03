# Phase 6.5: Calendar Date Picker + Date Menus

目标：把 Phase 5.9 的轻量日期选择器升级为更接近原版 Obsidian Tasks date picker/date menu 的 Neovim 体验。

## 原版依据

原版实现和文档位于：

- `../obsidian-tasks/docs/Editing/Editing Dates.md`
- `../obsidian-tasks/src/ui/Menus/DatePicker.ts`
- `../obsidian-tasks/src/ui/Menus/DateMenu.ts`
- `../obsidian-tasks/src/ui/DateEditor.svelte`
- `../obsidian-tasks/src/DateTime/Postponer.ts`

原版日期编辑能力包括：

- 在编辑任务时选择 due/start/scheduled/done/cancelled/created。
- 可以清空已有日期。
- date menu 提供常用日期和 postpone/advance 类动作。
- date picker 提供 calendar-style UI。

## 已实现

- `date_picker.pick()` 保留旧的 `vim.ui.select` picker。
- select picker 新增：
  - `Advance 1 day`
  - `Postpone 1 day`
  - `Calendar...`
- 新增 floating calendar buffer：

```text
obsidian-tasks://date-picker
```

- calendar 支持：
  - `h` / `l` 前后一天。
  - `k` / `j` 前后一周。
  - `H` / `L` 前后一个月。
  - `<CR>` 选择当前日期。
  - `c` 清空日期。
  - `q` / `<Esc>` 关闭。
- calendar header 会显示当前月份、年份和 date field。
- 如果调用方传入当前日期，会显示 `Current: YYYY-MM-DD`。
- 支持字段：
  - `due`
  - `scheduled`
  - `start`
  - `created`
  - `done`
  - `cancelled`
- `:ObsidianTasksPickDate [field]` 默认仍使用 select picker。
- `:ObsidianTasksPickDate! [field]` 强制打开 calendar picker。
- `setup({ date_picker = { style = "calendar" } })` 可把默认 picker 改为 calendar。
- form buffer 的 `gd` 通过 `date_picker.pick_for_form()` 进入同一套 picker。
- 普通 Markdown task 行和 form buffer 都会复用同一套日期选择逻辑。

## API

```lua
local date_picker = require("obsidian-tasks.date_picker")

date_picker.open_calendar(opts, callback)
date_picker.pick({
  field = "due",
  current_value = "2026-05-20",
  style = "calendar",
}, function(value)
  -- value is "YYYY-MM-DD" or "" when cleared.
end)
date_picker.pick_at_cursor({ field = "due", calendar = true })
date_picker.pick_for_form(buf, "due", {
  style = "calendar",
  on_select = function(value) end,
})
```

配置示例：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  date_picker = {
    style = "select", -- or "calendar"
  },
})
```

## 当前边界

- 还没有实现真正的鼠标右键 date context menu；Neovim 侧用 command、form keymap 和 picker 替代。
- advance/postpone 第一版只提供当前日期前后一天，更多粒度继续走 Today/Tomorrow/Next week/Custom 或 calendar 导航。
- calendar 是纯文本 floating buffer，没有鼠标点击日期格。
- date picker 仍只写 emoji format 日期字段，Dataview format 留到 Phase 6.7。

## Phase 6.5 验收

- 普通 Markdown task 行可用 `:ObsidianTasksPickDate! due` 打开 calendar 并写回 due date。
- 普通 Markdown task 行可用 `:ObsidianTasksPickDate! scheduled` 写回 scheduled date。
- 普通 Markdown task 行可用 calendar 的 `c` 清空当前字段日期。
- form buffer 日期字段可用 `gd` 打开 picker，并写回字段值。
- `h/l/j/k/H/L` navigation 能正确跨周和跨月。
- 旧 select picker 仍可用，并包含 `Calendar...` 入口。
- select picker 在当前字段已有日期时包含 `Advance 1 day` 和 `Postpone 1 day`。

## 自动测试

```sh
sh scripts/smoke_phase6_5.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase5_5.sh
sh scripts/smoke_phase6_4.sh
```
