# Phase 5: Editing Form + Advanced Query MVP

目标：在 Phase 4 的任务语义基础上，补上更接近 Obsidian Tasks 高级使用体验的第一批能力：更强的查询表达能力，以及可编辑任务字段的表单入口。

Phase 5 仍保持一个原则：先做原 Obsidian Tasks 中确实存在的能力，再按 Neovim 交互做轻量适配。`filter by function` 在原插件里是 JavaScript；本插件里对应为 Lua 表达式，并且默认关闭，需要显式开启。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_5_TEST.md`、`PHASE_5_1_TEST.md`、`PHASE_5_2_TEST.md`、`PHASE_5_3_TEST.md`、`PHASE_5_4_TEST.md`、`PHASE_5_5_TEST.md`、`PHASE_5_6_TEST.md`，headless smoke 见 `scripts/smoke_phase5.sh`、`scripts/smoke_phase5_1.sh`、`scripts/smoke_phase5_2.sh`、`scripts/smoke_phase5_3.sh`、`scripts/smoke_phase5_4.sh`、`scripts/smoke_phase5_5.sh`、`scripts/smoke_phase5_6.sh`。

已覆盖：

- Regex filters：
  - `description regex matches /.../i`
  - `tag regex matches /.../`
  - `path/root/folder/filename/heading/id/recurrence/status.name/status.type regex matches /.../`
  - `regex does not match`
- Boolean query：
  - 独立行 `OR` 分隔两个 AND filter group。
  - Phase 5.1 已支持括号表达式：`(A) AND ((B) OR (C))`、`NOT (A)`。
- Presets：
  - `setup({ presets = { name = "..." } })`
  - query 中 `preset name` 展开为完整 instruction lines。
  - Phase 5.2 已支持 `{{preset.name}}` 行内展开。
- Placeholders：
  - Phase 5.2 已支持 `{{query.file.*}}`。
  - function filter 中可读取 `query.file`。
- Query composition：
  - Phase 5.3 已支持 `global_query` / `globalQuery`。
  - 已支持 `ignore global query`。
  - 已支持 Query File Defaults 的 `TQ_*` frontmatter 注入。
- Layout directives：
  - Phase 5.4 已支持 `show/hide task count`。
  - 已支持 `show/hide backlink`，隐藏后仍能 toggle/save/jump/edit。
  - 已支持常用 task fields：priority、tags、dates、id、depends on、recurrence、on completion。
- Function filter：
  - `filter by function <lua expression>`
  - `filter by lua <lua expression>`
  - 需要 `enable_lua_filters = true`。
- 编辑表单：
  - `:ObsidianTasksEdit`
  - `:ObsidianTasksCreate [file]`
  - 结果 buffer 中 `e` 编辑当前任务。
  - Phase 5.5 已支持常用自然日期保存正规化。
  - form buffer 中 `gs` 选择 status，`gd` 在日期字段选择常用日期。
  - Phase 5.6 已支持 form buffer auto-suggest MVP。

仍留到后续打磨：

- Query File Defaults 的属性写入命令。
- Tree/toolbar/urgency 等更完整 layout。
- 更完整的 dependency editor 和 calendar picker。
- Dataview inline field 格式读写。
- Frontmatter properties 和 links。

## 配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",

  presets = {
    urgent_open = [[
not done
priority is above normal
]],
  },

  enable_lua_filters = true,
  global_query = "not done",
  inbox_file = "/path/to/vault/Inbox.md",
})
```

兼容 camelCase：

- `queryPresets`
- `enableLuaFilters`
- `globalQuery`
- `inboxFile`

## Advanced Query

### Regex

```tasks
not done
description regex matches /review|plan/i
path regex does not match /Archive/
tag regex matches /#work/
```

当前使用 Neovim `vim.regex()` 执行，语法接近 Vim very-magic pattern，而不是完整 JavaScript Regex。常见的字面文本、`|`、`^`、`$`、简单字符类可用；更复杂的 JS regex 需要后续继续适配。

### Boolean

Phase 5.1 支持括号 Boolean 表达式：

```tasks
(not done) AND ((tag includes #work) OR (tag includes #home))
```

也支持：

```tasks
NOT (done)
(not done) AND NOT (description includes someday)
```

Phase 5 的独立行 `OR` 分组仍保留：

```tasks
not done
tag includes #work
OR
not done
tag includes #home
```

语义：

- `OR` 之前的多行 filter 是一个 AND group。
- `OR` 之后的多行 filter 是另一个 AND group。
- 多个 `OR` 可以形成多个 group。

### Preset

```lua
require("obsidian-tasks").setup({
  presets = {
    open_work = [[
not done
tag includes #work
]],
  },
})
```

Query：

```tasks
preset open_work
sort by due
```

`preset name` 会展开成完整 query instruction lines。Phase 5.2 也支持单行 preset 在行内用 `{{preset.name}}`：

```tasks
({{preset.alpha_filter}}) OR (description includes Inbox)
```

如果 preset 展开成多行 filter，更适合继续使用完整行 `preset name` 或普通多行 query。

### Placeholders

Phase 5.2 支持 query source 文件相关 placeholder：

```tasks
path includes {{query.file.path}}
folder includes {{query.file.folder}}
```

支持字段见 `PHASE_5_2.md`。这些 placeholder 会按 query block 或 config query 的 `source_path` 展开；纯手写 `:ObsidianTasksQuery ...` 默认没有 query file context。

### Query Composition

Phase 5.3 会按原版顺序合成最终 query：

1. `global_query` / `globalQuery`
2. Query File Defaults，也就是 query 所在 Markdown 文件 frontmatter 里的 `TQ_*`
3. 当前 tasks code block 或 config query source

如果 Query File Defaults 或当前 query source 中出现：

```tasks
ignore global query
```

则跳过 `global_query`。

Query File Defaults 示例：

```yaml
---
TQ_extra_instructions: |-
  folder includes {{query.file.folder}}
TQ_short_mode: true
TQ_show_task_count: true
---
```

Phase 5.4 已让常用显示 directives 影响 result buffer 和 preview：

```tasks
hide task count
hide backlink
hide priority
hide tags
hide due date
```

`show tree`、`show toolbar`、`show urgency` 等更完整 UI 能力仍留到后续。

### Function Filter

```lua
require("obsidian-tasks").setup({
  enable_lua_filters = true,
})
```

Query：

```tasks
filter by function task.description:find("review", 1, true) ~= nil
```

为了贴近原插件的 instruction 名称，`filter by function` 被保留；表达式内容是 Lua，不是 JavaScript。可用变量：

- `task`
- `query.all_tasks`
- `query.allTasks`
- `query.file`
- `query.query_file`
- `query.queryFile`

如果未启用 `enable_lua_filters`，query 会显示错误。

## Editing Form

### Edit

在 Markdown 任务行或 Tasks result buffer 的任务行上执行：

```vim
:ObsidianTasksEdit
```

结果 buffer 中也可以按：

```vim
e
```

会打开一个 `obsidian-tasks://form/edit` buffer：

```text
description: Write Phase 5 docs #task
status: Todo
priority: high
created:
start:
scheduled:
due: 2026-05-20
done:
cancelled:
recurrence:
id:
depends_on:
on_completion:
```

保存：

```vim
<C-S>
:write
```

### Create

在 Markdown 文件中执行：

```vim
:ObsidianTasksCreate
```

保存表单后，新任务插入到当前行下方。

也可以指定目标文件：

```vim
:ObsidianTasksCreate /path/to/vault/Inbox.md
```

如果当前 buffer 不是 Markdown 文件，会尝试写入 `setup({ inbox_file = ... })`。

### Form Dates And Pickers

Phase 5.5 支持 form date fields 使用常用自然日期：

```text
created: 6 oct
start: 2 weeks
scheduled: +3
due: tomorrow
```

保存时会正规化为 `YYYY-MM-DD`；非法日期会阻止保存并保留 form buffer。

Form 快捷键：

- `gs`：选择 status。
- `gd`：在日期字段上选择常用日期。
- `<C-Space>` / `<C-X><C-U>`：在支持字段触发补全建议。

### Form Auto-Suggest

Phase 5.6 在 form buffer 里提供轻量补全源：

```lua
require("obsidian-tasks").setup({
  auto_suggest_in_editor = true,
  auto_suggest_min_chars = 0,
  auto_suggest_max_items = 20,
})
```

支持字段：

- `status`
- `priority`
- date fields
- `recurrence`
- `id`
- `depends_on`
- `on_completion`

## Phase 5 验收

- Regex filters 可以匹配 description/tag/path/id/recurrence/status 等字段。
- `OR` 可以组合两个或多个 AND group。
- `preset name` 可以展开 config presets。
- `{{preset.name}}` 和 `{{query.file.*}}` 可以按 query source 展开。
- `global_query`、`ignore global query` 和 Query File Defaults 可以按顺序组合。
- `show/hide` 常用 layout directives 可以影响 result buffer 和 preview。
- `filter by function` 默认禁用，开启后可执行 Lua 表达式。
- `:ObsidianTasksEdit` 可以编辑当前任务并写回源行。
- `:ObsidianTasksCreate` 可以创建新任务。
- 表单日期字段可以解析常用自然日期并阻止非法日期保存。
- Form buffer 可以对常用字段提供 auto-suggest。
- Phase 4 smoke 无回归。
