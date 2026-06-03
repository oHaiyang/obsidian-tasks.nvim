# Phase 6.6: Auto-Suggest Polish + Task Search Suggestions

目标：在 Phase 5.7/5.8/Native Completion Adapter 的基础上，补齐更接近原版 Obsidian Tasks auto-suggest 的任务搜索建议能力。

## 原版依据

原版实现和文档位于：

- `../obsidian-tasks/docs/Editing/Auto-Suggest.md`
- `../obsidian-tasks/src/Commands/CreateOrEditTaskParser.ts`
- `../obsidian-tasks/src/ui/EditTask.svelte`
- `../obsidian-tasks/src/ui/EditInstructions`

原版编辑任务时，会根据上下文建议 priority、date、recurrence、id、dependsOn、onCompletion 等字段。Dependency/id 场景里，用户需要能按任务信息找到目标任务，而不是只靠手写 id。

## 已实现

- 新增 `lua/obsidian-tasks/task_search.lua`，集中提供：
  - `candidate_tasks(opts)`：扫描 vault 中可作为候选的 tasks。
  - `format_candidate(task, opts)`：统一格式化任务描述、文件、行号和 id。
  - `completion_item(task, opts)`：生成 completion item，并携带 task 元数据。
- `dependency_editor.lua` 复用 `task_search.candidate_tasks()` 和 `task_search.format_candidate()`。
- `completion.lua` 的 `depends_on` 建议从 id-only 升级为 task search items：
  - `word` 仍是 task id。
  - `abbr` 显示任务描述、来源文件、行号和 id。
  - `filter_text` 支持按 id、description、filename、path 前缀匹配。
  - `data` 带 `kind = "task"`、`file_path`、`line_number`、`id`、`needs_id` 等元数据。
- `completion.markdown_context()` 会记录当前 task 来源，用于排除当前任务自身。
- form buffer 的 `depends_on` 补全也会排除当前正在编辑的任务自身。
- `nvim-cmp` source 会把 task item 的元数据透传到 cmp item，并把 documentation 展示为任务来源说明。
- 原生 completion adapter 保持原触发策略，只透传当前 task context。
- 新增 public API：

```lua
local completion = require("obsidian-tasks.completion")

completion.task_search_items({
  state = { vault_path = "/path/to/vault" },
  require_id = true,
})

completion.task_id_items({
  state = { vault_path = "/path/to/vault" },
})

completion.date_items("tom", {
  context = "markdown",
  state = { today = "2026-05-22" },
})

completion.recurrence_items("every w")
```

## 当前边界

- 普通 completion confirm 不会自动给目标任务写入 `🆔 id`。这避免补全确认时产生跨文件副作用。
- 没有 id 的任务可通过 `completion.task_search_items({ require_id = false })` 暴露为 `needs_id` 候选，但 `depends_on` 补全默认只插入已有 id 的任务。
- 真正“选择无 id 任务并自动生成 id + 写回 target + 添加 dependsOn”仍由 `:ObsidianTasksAddDependency` 和 form `gD` 负责。
- 任务搜索第一版使用前缀匹配，不做 fuzzy scoring。
- Dataview format 的补全仍留到 Phase 6.7。

## Phase 6.6 验收

- `depends_on` 补全可以按 task id 搜索。
- `depends_on` 补全可以按 task description 前缀搜索。
- 补全候选显示任务描述、文件、行号和 id。
- 当前正在编辑的任务不会被推荐为自己的 dependency。
- form buffer 和普通 Markdown task 行共享 task search suggestions。
- `nvim-cmp` source 中 task items 带有 documentation 和 `data.kind = "task"`。
- 原生 completion adapter 不改变自动触发边界，不复发 backspace 隐藏文本问题。

## 自动测试

```sh
sh scripts/smoke_phase6_6.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_8.sh
sh scripts/smoke_phase5_7.sh
sh scripts/smoke_phase5_6.sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase6_native_completion.sh
```
