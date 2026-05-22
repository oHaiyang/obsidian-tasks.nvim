# Phase 6.2: Urgency Score + Urgency Layout

目标：实现原版 Obsidian Tasks 的 urgency score，并让 `show urgency`、`hide urgency`、`sort by urgency`、`group by urgency` 和 `task.urgency` 可用。

## 原版依据

原版实现位于：

- `../obsidian-tasks/src/Task/Urgency.ts`
- `../obsidian-tasks/src/Query/Filter/UrgencyField.ts`
- `../obsidian-tasks/docs/Advanced/Urgency.md`

原版 urgency 只由四个维度相加：

1. Due date
2. Priority
3. Scheduled date
4. Start date

它不考虑 task status，也不考虑 dependencies。

## 计算规则

Due date：

- due 7 天前或更早：`12.0`
- due 在 7 天前到 14 天后之间：线性映射到 `12.0` 到 `2.4`
- due 14 天后以后：`2.4`
- 无有效 due date：`0.0`

Priority：

- highest：`9.0`
- high：`6.0`
- medium：`3.9`
- none / normal：`1.95`
- low：`0.0`
- lowest：`-1.8`

Scheduled：

- scheduled today 或更早：`5.0`
- scheduled tomorrow 或更晚：`0.0`
- 无有效 scheduled date：`0.0`

Start：

- start tomorrow 或更晚：`-3.0`
- start today 或更早：`0.0`
- 无有效 start date：`0.0`

示例：

```markdown
- [ ] #task Due today medium 🔼 📅 2026-05-16
```

在 `today = 2026-05-16` 时 urgency 为：

```text
8.8 + 3.9 = 12.7
```

## 已实现

- 新增 `lua/obsidian-tasks/urgency.lua`：
  - `score(task, opts)`
  - `enrich(task, opts)`
  - `format(task)`
- `task.parse_line()` 会为每个 task 注入 `task.urgency`。
- scanner 会把 `today` 透传给 task parser。
- finder 会把 `opts.today` 透传给 scanner。
- `sort by urgency` 支持高分在前，`sort by urgency reverse` 支持低分在前。
- `group by urgency` 支持两位小数分组，并按高分到低分排序。
- `show urgency` 在 result buffer 和 inline preview 的 task body 中显示 `urgency 12.70`。
- `short mode` 下 `show urgency` 只显示 `12.70`。
- `hide urgency` 明确隐藏 urgency。
- Lua function filter 可读取 `task.urgency`。

## 当前边界

- 没有实现 `urgency` 普通过滤器。原版 `UrgencyField` 也明确不支持直接过滤 urgency。
- 没有改变默认排序。原版默认排序会使用 urgency，但当前插件仍只在 query 写了 `sort by urgency` 时应用。
- `group by urgency reverse` 暂未实现；当前只实现默认高分到低分。

## Phase 6.2 验收

- task model 中每个 task 有 numeric `urgency`。
- `show urgency` 能显示两位小数。
- `hide urgency` 不显示 urgency。
- `short mode` + `show urgency` 不显示 `urgency` 文本前缀。
- `sort by urgency` 高分在前。
- `sort by urgency reverse` 低分在前。
- `group by urgency` 分组 heading 使用两位小数，并高分在前。
- `filter by function task.urgency > ...` 可用。
- Phase 5.4/5/4 smoke 无回归。
