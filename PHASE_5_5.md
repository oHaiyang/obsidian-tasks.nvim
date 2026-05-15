# Phase 5.5: Edit Form Ergonomics

目标：让 Phase 5 的 create/edit form 更接近原 Obsidian Tasks 的编辑体验，先补日期输入和轻量 picker。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_5_5_TEST.md`，headless smoke 见 `scripts/smoke_phase5_5.sh`。

已覆盖：

- 日期字段保存时自动正规化为 `YYYY-MM-DD`。
- 非法日期会阻止保存，并保留 form buffer。
- `set_created_date = true` 创建任务时支持通过 config/opts 注入 `today`，便于测试。
- 表单快捷键：
  - `gs`：选择 status。
  - `gd`：在 date field 上选择常用日期。

## 支持的日期输入

所有 form date fields 都支持：

- `YYYY-MM-DD`
- `today`
- `tomorrow`
- `yesterday`
- `+N`
- `-N`
- `N days`
- `N weeks`
- `N months`
- `N years`
- `in N days/weeks/months/years`
- `next week/month/year`
- `last week/month/year`
- `6 oct`
- `oct 6`
- `6 oct 2026`
- `oct 6 2026`

这些能力来自 `date.parse_date_expr()`，所以 query date filters 也可以复用同一套日期表达式。

## 表单快捷键

在 `obsidian-tasks://form/...` buffer 中：

```vim
gs
```

打开 status picker，并写入 `status:` 字段。

在 `created/start/scheduled/due/done/cancelled` 任一字段所在行：

```vim
gd
```

打开 date picker，提供：

- Clear
- Today
- Tomorrow
- In 1 week
- In 2 weeks
- In 1 month

## Phase 5.5 验收

- 编辑任务时，把 `due: tomorrow` 保存为绝对日期。
- 编辑任务时，把 `start: 2 weeks`、`scheduled: +3` 保存为绝对日期。
- `6 oct` / `oct 6` 能按当前年份保存。
- 非法日期不会写回源文件。
- 创建任务时 `set_created_date = true` 可填入 created date。
- Phase 5.4/5.3/5.2/5.1/5/4/3/2 smoke 无回归。

## 已知限制

- 还没有 continuous auto-suggest popup。
- 还没有完整 calendar picker。
- `6 oct` 未写年份时使用当前 `today` 所在年份，不自动跳到下一年。
