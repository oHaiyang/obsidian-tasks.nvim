# Phase 1: Task Core MVP

目标：先用纯 Lua 建立稳定的任务核心模型，让后续查询语言、循环任务、状态机和 UI 都依赖同一套 parser/serializer。

本阶段只做底层能力，不追求和 Obsidian Tasks 的全部查询语言、modal UI、Dataview 格式、复杂 recurrence 行为完全对齐。

## 设计原则

- 核心逻辑使用 Lua。
- `task.lua` 这类核心模块尽量保持纯函数，不直接依赖 `vim.api`。
- 扫描、显示、写回等 Neovim 交互逻辑留在 `finder.lua`、`display.lua`、`core.lua`。
- 先保证“一行任务怎么读、怎么改、怎么无损写回”可靠。

## 需求范围

### P1.1 Task parser / serializer

状态：已实现第一版，位于 `lua/obsidian-tasks/task.lua`。

实现 `lua/obsidian-tasks/task.lua`：

- 识别 Markdown task 行：
  - `- [ ] task`
  - `* [ ] task`
  - `+ [ ] task`
  - `1. [ ] task`
  - `1) [ ] task`
  - 带缩进和 `>` blockquote/callout 前缀的任务
- 保留字段：
  - `indentation`
  - `list_marker`
  - `status_symbol`
  - `status`
  - `body`
  - `text`
  - `original_markdown`
  - `file_path`
  - `line_number`
- 解析 Tasks Emoji Format 常用字段：
  - priority: `🔺`、`⏫`、`🔼`、`🔽`、`⏬`
  - dates: `➕`、`🛫`、`⏳`、`📅`、`❌`、`✅`
  - recurrence rule: `🔁 ...`
  - on completion: `🏁 keep/delete`
  - dependencies: `🆔 id`、`⛔ dependsOn`
  - block link: `^block-id`
  - tags
- serializer 可以把 Task 对象写回 Markdown 行，并保留原始缩进和 list marker。

验收：

- parse -> serialize 后，未修改 task 时应尽量保持语义一致。
- 修改 status 后，只改变 checkbox 里的 status symbol，不误改描述里的 `[x]`。

### P1.2 Global filter

状态：已实现第一版，支持 `global_filter` 和兼容写法 `globalFilter`。

- 支持配置 `global_filter` 或兼容 `globalFilter`。
- 未设置 global filter 时，所有 checklist item 都算任务。
- 设置 global filter 时，只有 body 中包含该字符串的 checklist item 才算任务。
- 去掉当前 `rg` 中硬编码的 `#t`。

### P1.3 Scanner MVP

状态：已实现第一版，位于 `lua/obsidian-tasks/scanner.lua`。

- 扫描 vault 中 `.md` 文件。
- 跳过 fenced code block 中的候选任务。
- 将候选 task 行交给 `task.parse_line()` 判断。
- finder 不再自己解析任务行。

### P1.4 Write-back / toggle

状态：已实现第一版。查询结果写回和普通 Markdown buffer 当前行 toggle 已改用 parser/serializer。

- 查询结果 buffer 中 toggle 后，源文件写回使用 Task serializer。
- 普通 Markdown buffer 中也可以直接 toggle 当前行任务。
- 写回时保留原始 task line 的缩进、list marker 和 metadata。

## 明确暂缓

- 完整 Tasks 查询语言。
- Boolean query、presets、placeholders、query file defaults。
- Dataview task format。
- Recurrence 下一次任务计算。
- Custom status registry 和 status type 行为。
- Auto-suggest。
- Create/Edit task modal。
- Frontmatter properties 和 links。
