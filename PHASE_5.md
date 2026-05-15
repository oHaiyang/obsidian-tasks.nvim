# Phase 5: Editing Form + Advanced Query MVP

目标：在 Phase 4 的任务语义基础上，补上更接近 Obsidian Tasks 高级使用体验的第一批能力：更强的查询表达能力，以及可编辑任务字段的表单入口。

Phase 5 仍保持一个原则：先做原 Obsidian Tasks 中确实存在的能力，再按 Neovim 交互做轻量适配。`filter by function` 在原插件里是 JavaScript；本插件里对应为 Lua 表达式，并且默认关闭，需要显式开启。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_5_TEST.md`，headless smoke 见 `scripts/smoke_phase5.sh`。

已覆盖：

- Regex filters：
  - `description regex matches /.../i`
  - `tag regex matches /.../`
  - `path/root/folder/filename/heading/id/recurrence/status.name/status.type regex matches /.../`
  - `regex does not match`
- 简化 Boolean OR：
  - 多行 query 中单独一行 `OR` 分隔两个 AND filter group。
- Presets：
  - `setup({ presets = { name = "..." } })`
  - query 中 `preset name` 展开为完整 instruction lines。
- Function filter：
  - `filter by function <lua expression>`
  - `filter by lua <lua expression>`
  - 需要 `enable_lua_filters = true`。
- 编辑表单：
  - `:ObsidianTasksEdit`
  - `:ObsidianTasksCreate [file]`
  - 结果 buffer 中 `e` 编辑当前任务。

仍留到后续打磨：

- 完整括号 Boolean parser：`(A) AND ((B) OR (C))`。
- `{{preset.name}}`、`{{query.file.*}}` placeholders。
- Query File Defaults。
- Auto-suggest popup。
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
  inbox_file = "/path/to/vault/Inbox.md",
})
```

兼容 camelCase：

- `queryPresets`
- `enableLuaFilters`
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

### OR

原 Obsidian Tasks 支持括号内 Boolean 组合。Phase 5 先实现多行 `OR` 分组：

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

`preset name` 必须展开成完整 query instruction lines。Phase 5 还不支持在一行内部用 `{{preset.name}}`。

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

## Phase 5 验收

- Regex filters 可以匹配 description/tag/path/id/recurrence/status 等字段。
- `OR` 可以组合两个或多个 AND group。
- `preset name` 可以展开 config presets。
- `filter by function` 默认禁用，开启后可执行 Lua 表达式。
- `:ObsidianTasksEdit` 可以编辑当前任务并写回源行。
- `:ObsidianTasksCreate` 可以创建新任务。
- Phase 4 smoke 无回归。
