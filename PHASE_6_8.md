# Phase 6.8: Frontmatter Properties + Links + Scripting Surface

目标：扩展 task/query 的 Lua function filter surface，让它更接近原版 Obsidian Tasks custom filter 能访问的 task file properties 和 links。

## 原版依据

原版实现和文档位于：

- `../obsidian-tasks/docs/Scripting/Task Properties.md`
- `../obsidian-tasks/docs/Scripting/Query Properties.md`
- `../obsidian-tasks/docs/Scripting/JavaScript in Tasks Queries.md`
- `../obsidian-tasks/docs/Getting Started/Obsidian Properties.md`
- `../obsidian-tasks/src/Scripting/TaskExpression.ts`
- `../obsidian-tasks/src/Scripting/TasksFile.ts`
- `../obsidian-tasks/src/Scripting/QueryContext.ts`
- `../obsidian-tasks/src/Task/Link.ts`
- `../obsidian-tasks/src/Task/LinkResolver.ts`

## 已实现

- 新增 `lua/obsidian-tasks/frontmatter.lua`：
  - 支持 `---` frontmatter block。
  - 支持结束符 `---` 和 `...`。
  - 支持 scalar：string、quoted string、boolean、number、null。
  - 支持 inline array：`[a, b]`。
  - 支持简单 block list：

```yaml
tags:
  - project
  - focus
```

- 新增 `lua/obsidian-tasks/links.lua`：
  - wikilink：`[[Note]]`、`[[Note#Heading]]`、`[[Note|Alias]]`。
  - markdown link：`[Label](path.md)`。
- `scanner.scan_file()` 每个文件只解析一次 frontmatter，并注入给该文件的全部 tasks。
- task model 新增：
  - `task.frontmatter`
  - `task.properties`
  - `task.file.frontmatter`
  - `task.file.properties`
  - `task.file.tags`
  - `task.file.aliases`
  - `task.file.cssclasses`
  - `task.file.classes`
  - `task.links`
  - `task.outlinks`
- query file context 新增：
  - `query.file.frontmatter`
  - `query.file.properties`
  - `query.file.tags`
  - `query.file.aliases`
  - `query.file.cssclasses`
  - `query.file.classes`
- `query_file_defaults.lua` 复用同一套 frontmatter parser。
- Lua function filter 环境新增 `vim`，支持：

```tasks
filter by function vim.tbl_contains(task.file.tags or {}, "project")
```

## 示例

```tasks
filter by function task.frontmatter.area == "work"
filter by function vim.tbl_contains(task.file.tags or {}, "project")
filter by function #(task.links or {}) > 0
```

query file properties：

```tasks
filter by function vim.tbl_contains(query.file.tags or {}, "dashboard")
```

## 当前边界

- 不是完整 YAML parser；复杂 nested object 会保留为 block string 或忽略结构。
- frontmatter link 不解析进 `task.links`；本阶段只解析 task line links。
- wikilink path resolution 不做真实 vault path 解析，只暴露 destination/path/subpath/display。
- markdown link 只做常见 `[label](destination)`。
- 不解析 embeds `![[...]]` 的特殊语义，当前会作为普通 wikilink 进入 links。

## Phase 6.8 验收

- `task.frontmatter.area == "work"` 可用于 function filter。
- `task.file.tags`、`task.file.aliases`、`task.file.cssclasses` 可用于 function filter。
- `task.links` / `task.outlinks` 包含 task line wikilinks 和 markdown links。
- `query.file.tags` 可用于 function filter。
- Query File Defaults 读取不回归。
- 没有 frontmatter 的文件不报错。

## 自动测试

```sh
sh scripts/smoke_phase6_8.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_3.sh
sh scripts/smoke_phase5_10.sh
sh scripts/smoke_phase5.sh
```
