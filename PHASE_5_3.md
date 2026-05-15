# Phase 5.3: Query Composition + Query File Defaults

目标：补齐 Obsidian Tasks 的 query 组合语义，让每次执行 query 前都能按固定顺序合成最终查询。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_5_3_TEST.md`，headless smoke 见 `scripts/smoke_phase5_3.sh`。

已覆盖：

- `global_query` / `globalQuery`：
  - 从 `setup()` 配置中读取。
  - 自动注入到每个 query 前面。
- `ignore global query`：
  - 可以出现在 code block query 中。
  - 可以出现在 `TQ_extra_instructions` 中。
  - 如果写在 global query 自己里面，会被忽略。
- Query File Defaults：
  - 从 query 所在 Markdown 文件 frontmatter 读取 `TQ_*` 属性。
  - 自动生成 query instructions。
  - 支持 `TQ_extra_instructions` 多行文本。
  - 支持 `{{query.file.*}}` 和 `{{preset.*}}` placeholder 后续展开。
- 组合顺序：
  - `global query`
  - `Query File Defaults`
  - 当前 query source
- layout 类 instructions 先进入 `plan.layout`：
  - `explain`
  - `short mode` / `full mode`
  - `show ...` / `hide ...`
  - 真正影响结果视图放到 Phase 5.4。

## 配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_query = [[
not done
path does not include Archive
]],
})
```

兼容 camelCase：

```lua
require("obsidian-tasks").setup({
  globalQuery = "not done",
})
```

## Query File Defaults

在包含 tasks code block 的 Markdown 文件顶部写 frontmatter：

```yaml
---
TQ_extra_instructions: |-
  folder includes {{query.file.folder}}
  sort by due
TQ_short_mode: true
TQ_show_task_count: true
---
```

该文件内所有 tasks query 会先自动注入：

```tasks
short mode
show task count
folder includes {{query.file.folder}}
sort by due
```

然后再追加 code block 自己的 query。

## 支持的 TQ 属性

当前按原版顺序支持：

- `TQ_show_toolbar`
- `TQ_explain`
- `TQ_short_mode`
- `TQ_show_tree`
- `TQ_show_tags`
- `TQ_show_id`
- `TQ_show_depends_on`
- `TQ_show_priority`
- `TQ_show_recurrence_rule`
- `TQ_show_on_completion`
- `TQ_show_created_date`
- `TQ_show_start_date`
- `TQ_show_scheduled_date`
- `TQ_show_due_date`
- `TQ_show_cancelled_date`
- `TQ_show_done_date`
- `TQ_show_urgency`
- `TQ_show_backlink`
- `TQ_show_edit_button`
- `TQ_show_postpone_button`
- `TQ_show_task_count`
- `TQ_extra_instructions`

其中显示相关属性会被解析并保存在 `plan.layout`，真正渲染控制放到下一阶段。

## ignore global query

如果某个 query 不想受全局 query 影响：

```tasks
ignore global query
description includes demo
```

也可以放到文件 frontmatter：

```yaml
---
TQ_extra_instructions: |-
  ignore global query
  folder includes {{query.file.folder}}
---
```

## Phase 5.3 验收

- `global_query` 能自动限制所有 query。
- `ignore global query` 能跳过 `global_query`。
- `TQ_extra_instructions` 能注入 filter/sort/group 等普通 query instruction。
- Query File Defaults 能使用 `{{query.file.*}}` placeholders。
- `TQ_short_mode`、`TQ_show_task_count` 等 layout directives 不再报 unsupported instruction。
- preview 和 result panel 使用同一套 composition。
- Phase 5.2/5.1/5/4/3/2 smoke 无回归。

## 已知限制

- frontmatter 解析是轻量 YAML 子集，优先覆盖 Obsidian 常见的 `key: true/false` 和 `|-` 多行文本。
- `TQ_*` 属性写入命令还没有实现。
- layout directives 已解析，但显示隐藏行为放到 Phase 5.4。
- Line continuations 还没有实现。
