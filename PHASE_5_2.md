# Phase 5.2: Query Context + Placeholders

目标：补上 Phase 5/5.1 留下的 placeholder 能力，让查询可以感知“查询所在文件”，并允许 preset 在 query 行内展开。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_5_2_TEST.md`，headless smoke 见 `scripts/smoke_phase5_2.sh`。

已覆盖：

- `{{query.file.*}}` placeholders：
  - `{{query.file.path}}`
  - `{{query.file.path_without_extension}}`
  - `{{query.file.pathWithoutExtension}}`
  - `{{query.file.root}}`
  - `{{query.file.folder}}`
  - `{{query.file.filename}}`
  - `{{query.file.filename_without_extension}}`
  - `{{query.file.filenameWithoutExtension}}`
- `{{preset.name}}` 可以在 query 任意位置展开，包括 Boolean expression 中。
- `preset name` 展开时也会继续展开 placeholder。
- `filter by function` 的 Lua 表达式中可以读取 `query.file`。
- block query、config query、preview、panel refresh 都会把 query source context 传给 parser。
- 提供 3 个 nvim 内置 shortcut preset：
  - `preset this_file` -> `path includes {{query.file.path}}`
  - `preset this_folder` -> `folder includes {{query.file.folder}}`
  - `preset this_root` -> `root includes {{query.file.root}}`

## 查询文件上下文

`query.file` 指的是查询来源文件，不是当前被匹配的 task 文件。

对于 Markdown 中的 tasks code block：

```tasks
path includes {{query.file.path}}
```

会展开成：

```tasks
path includes /path/to/current/query/file.md
```

因此它只匹配当前 query block 所在文件中的任务。

对于 config query，可以在 query source 中显式提供 `source_path`：

```lua
require("obsidian-tasks").setup({
  queries = {
    dashboard = {
      source_path = "/path/to/vault/Dashboard.md",
      source_line = 1,
      query = "preset this_file",
    },
  },
})
```

纯手写的 `:ObsidianTasksQuery ...` 默认没有 query file context；如果使用 `{{query.file.*}}` 会进入 query error buffer。

## Preset Placeholder

配置：

```lua
require("obsidian-tasks").setup({
  presets = {
    project_folder = "folder includes {{query.file.folder}}",
    alpha_filter = "description includes Alpha",
    open_work = [[
not done
tag includes #work
]],
  },
})
```

Query：

```tasks
{{preset.project_folder}}
sort by due
```

也可以放进 Boolean：

```tasks
({{preset.alpha_filter}}) OR (description includes Inbox)
```

注意：Boolean operand 仍需要能解析成单个 filter；如果 preset 展开成多行 filter，就更适合用完整行 `preset name` 或普通多行 query。

## Function Filter Context

```tasks
filter by function task.file.folder == query.file.folder
```

可用变量：

- `task`：当前 task。
- `query.all_tasks` / `query.allTasks`：本次扫描到的全部任务。
- `query.file`：query source 文件信息。
- `query.query_file` / `query.queryFile`：`query.file` 的别名。

## Phase 5.2 验收

- tasks code block 中的 `{{query.file.path}}` 和 `{{query.file.folder}}` 能按 block 所在文件展开。
- `preset name` 支持 preset 内部 placeholder。
- `{{preset.name}}` 支持行内展开，并能用于 Boolean expression。
- Lua function filter 能通过 `query.file` 读取查询文件上下文。
- preview 渲染使用同一套 query source context。
- Phase 5.1/5/4/3/2 smoke 无回归。
