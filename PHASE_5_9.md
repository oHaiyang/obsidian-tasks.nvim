# Phase 5.9: Dependency Editor + Better Date Picker

目标：补上更接近原版 Obsidian Tasks 编辑体验的依赖选择和日期选择能力，让用户不必手动记 task id 或输入常用日期。

状态：已实现第一版，手动测试步骤见 `PHASE_5_9_TEST.md`，headless smoke 见 `scripts/smoke_phase5_9.sh`。

## 范围

新增模块：

- `lua/obsidian-tasks/dependency_editor.lua`
- `lua/obsidian-tasks/date_picker.lua`

新增命令：

```vim
:ObsidianTasksAddDependency
:ObsidianTasksPickDate [field]
```

新增 `<Plug>` mapping：

```vim
<Plug>(ObsidianTasksAddDependency)
<Plug>(ObsidianTasksPickDate)
```

Form buffer 新增：

- `gD`：选择依赖任务并写入 `depends_on` field。
- `gd`：增强为统一 date picker，支持 Clear、Today、Tomorrow、Yesterday、Next week、Next month、Custom input。

## Dependency Editor

依赖选择器会扫描 vault 中的 tasks：

- 展示任务描述、文件、行号和已有 id。
- 如果被选任务已有 `🆔 id`，直接使用。
- 如果被选任务没有 id，自动生成一个轻量 id 并写回被选任务。
- 把 id 添加到当前任务的 `⛔ dependsOn`。
- 已存在的 id 不会重复添加。

普通 Markdown task 行：

```vim
:ObsidianTasksAddDependency
```

Form buffer：

```vim
gD
```

## Better Date Picker

Form buffer：

```vim
gd
```

普通 Markdown task 行：

```vim
:ObsidianTasksPickDate due
:ObsidianTasksPickDate scheduled
:ObsidianTasksPickDate start
```

可选 field：

- `due`
- `scheduled`
- `start`
- `created`
- `done`
- `cancelled`

Date picker 支持：

- Clear
- Today
- Tomorrow
- Yesterday
- Next week
- In 1 week
- In 2 weeks
- Next month
- In 1 month
- Custom input

## 已知限制

- 依赖选择器目前用 `vim.ui.select()`，还不是完整 modal。
- 自动生成 id 是稳定的轻量格式，例如 `task-20260516-3`，不是原版完整随机 ID 策略。
- 普通 task 行 date picker 默认操作传入的 field，不会根据光标最近 emoji 自动判断 field。

## Phase 5.9 验收

- 普通 task 行可以选择依赖并写入 `⛔ id`。
- 被依赖任务没有 id 时会自动写回 `🆔 id`。
- Form buffer 可以用 `gD` 添加依赖 id。
- Date picker 可以设置、替换、清空普通 task 行日期。
- Form buffer `gd` 支持更多日期选项和 custom input。
- Phase 5.8/5.7/5.6 smoke 无回归。
