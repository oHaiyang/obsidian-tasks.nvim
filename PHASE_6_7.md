# Phase 6.7: Dataview Task Format MVP

目标：支持原版 Obsidian Tasks 的 Dataview inline field task format MVP，让 Dataview 格式任务可以被解析、查询，并在主要编辑入口中按 Dataview 格式写回。

## 原版依据

原版实现和文档位于：

- `../obsidian-tasks/docs/Reference/Task Formats/Dataview Format.md`
- `../obsidian-tasks/docs/Reference/Task Formats/About Task Formats.md`
- `../obsidian-tasks/src/TaskSerializer/DataviewTaskSerializer.ts`
- `../obsidian-tasks/src/TaskSerializer/DefaultTaskSerializer.ts`

已按原版确认 Dataview key：

| Task 字段 | Dataview key |
| --- | --- |
| priority | `priority` |
| created | `created` |
| start | `start` |
| scheduled | `scheduled` |
| due | `due` |
| done | `completion` |
| cancelled | `cancelled` |
| recurrence | `repeat` |
| on completion | `onCompletion` |
| id | `id` |
| depends on | `dependsOn` |

## 配置

默认仍是 Tasks emoji format：

```lua
require("obsidian-tasks").setup({
  task_format = "tasks",
})
```

启用 Dataview format：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  task_format = "dataview",
})
```

兼容 camelCase：

```lua
taskFormat = "dataview"
```

## 已实现

- `task.lua` 支持解析 Dataview inline fields：
  - `[priority:: high]`
  - `[created:: 2026-05-18]`
  - `[scheduled:: 2026-05-19]`
  - `[start:: 2026-05-19]`
  - `[due:: 2026-05-20]`
  - `[completion:: 2026-05-21]`
  - `[cancelled:: 2026-05-22]`
  - `[repeat:: every week]`
  - `[onCompletion:: delete]`
  - `[id:: abc]`
  - `[dependsOn:: a,b]`
- parser 也接受原版支持的 parenthesized inline field，例如 `(due:: 2026-05-20)`。
- `task.description` 会移除已支持的 Dataview inline fields；`task.body` 仍保留原始 body，供写回尽量保留原布局。
- query 能基于 Dataview 字段工作：
  - date filters
  - priority filters
  - `has id`
  - dependency filters
- status mutation 支持 Dataview date 写回：
  - DONE 写 `[completion:: YYYY-MM-DD]`
  - CANCELLED 写 `[cancelled:: YYYY-MM-DD]`
- postpone 和 date picker 写 Dataview date field。
- dependency editor 写：
  - `[id:: ...]`
  - `[dependsOn:: ...]`
- recurrence next task 会：
  - 推进 Dataview start/scheduled/due。
  - 移除 next task 的 `[completion:: ...]`、`[cancelled:: ...]`、`[id:: ...]`、`[dependsOn:: ...]`。
  - 按配置写 `[created:: ...]`。
- edit/create form 保存时，在 Dataview 模式下输出 Dataview inline fields，不写 emoji metadata。
- completion MVP：
  - Dataview 模式下普通 task token 建议 `[priority:: high]`、`[due:: `、`[dependsOn:: ` 等 inline field。
  - 在未闭合的 `[due:: tom` 中补 ISO date。
  - 在未闭合的 `[dependsOn:: b` 中补 task id。

## 当前边界

- MVP 只支持 Tasks 原版支持的 key，不读取任意 Dataview inline field 到 task model。
- 写回统一使用 square bracket `[]`，这与原版一致。
- 写回新增 inline field 时使用两个空格分隔，尽量避免 Obsidian Live Preview reference-link 显示问题。
- Dataview field 值不支持包含 `]` 或 `)` 的复杂内容。
- Dataview format 是全局配置；第一版不做同一个 vault 中 emoji/Dataview 混合自动识别。
- Dataview completion 不实现完整 fuzzy/search UI，只做当前 completion core 的上下文扩展。

## Phase 6.7 验收

- `task_format = "dataview"` 时能解析 due/priority/id/dependsOn。
- 查询 `due before ...`、`priority is high`、`has id` 对 Dataview task 生效。
- toggle done 不破坏 inline fields，并写 `[completion:: YYYY-MM-DD]`。
- date picker 写 Dataview field，不写 emoji。
- dependency editor 写 `[dependsOn:: id]`。
- edit form 保存 Dataview fields。
- 默认 `task_format = "tasks"` 行为无回归。

## 自动测试

```sh
sh scripts/smoke_phase6_7.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase5_5.sh
sh scripts/smoke_phase4.sh
sh scripts/smoke_phase5.sh
sh scripts/smoke_phase6_native_completion.sh
```
