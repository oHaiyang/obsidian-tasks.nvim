# Phase 5.10: Add Query File Defaults Properties

目标：补上原版 Obsidian Tasks 的 `Add all Query File Defaults properties` 命令，在当前 Markdown note 的 frontmatter 中写入全部支持的 `TQ_*` 属性。

## 原版行为

原版命令位于 `../obsidian-tasks/src/Commands/AddQueryFileDefaultsProperties.ts`，核心语义是：

- 读取当前文件 frontmatter。
- 取 `QueryFileDefaults().allPropertyNamesSorted()`。
- 对缺失属性写入 `null`。
- 已存在的属性和值保持不变。
- 如果全部属性已存在，提示无需更新。

Neovim 版本按同一语义实现，但在 buffer 中表现为 YAML 空值：

```yaml
TQ_show_tree:
```

这和 YAML `null` 一样会被当前 Query File Defaults 读取逻辑视为未设置。

## 已实现

- `query_file_defaults.all_property_names_sorted()`：返回按字母序排列的全部 `TQ_*` 属性名。
- `query_file_defaults.add_all_properties_to_lines(lines)`：纯 Lua 行级转换，方便测试。
- `query_file_defaults.add_all_properties_to_buffer(buf)`：对当前 buffer 写入缺失属性。
- `require("obsidian-tasks").add_query_file_defaults_properties()`：公开 Lua API。
- `:ObsidianTasksAddQueryFileDefaults`：主命令。
- `:ObsidianTasksAddQueryFileDefaultsProperties`：语义更完整的别名。

## 写入规则

无 frontmatter 的文件会在文件头插入：

```yaml
---
TQ_explain:
TQ_extra_instructions:
TQ_short_mode:
TQ_show_backlink:
TQ_show_cancelled_date:
TQ_show_created_date:
TQ_show_depends_on:
TQ_show_done_date:
TQ_show_due_date:
TQ_show_edit_button:
TQ_show_id:
TQ_show_on_completion:
TQ_show_postpone_button:
TQ_show_priority:
TQ_show_recurrence_rule:
TQ_show_scheduled_date:
TQ_show_start_date:
TQ_show_tags:
TQ_show_task_count:
TQ_show_toolbar:
TQ_show_tree:
TQ_show_urgency:
---
```

已有 frontmatter 的文件会把缺失的 `TQ_*` 行插入 closing delimiter 前：

```yaml
---
title: Dashboard
TQ_extra_instructions: |-
  folder includes {{query.file.folder}}
TQ_show_tree: true
TQ_explain:
# other missing TQ_* properties
---
```

已有值不会被重排或覆盖，尤其是 `TQ_extra_instructions: |-` 这类多行 block value。

## 当前边界

- 只处理标准 Markdown YAML frontmatter：第一行是 `---`，并且存在 closing `---` 或 `...`。
- 如果文件第一行是 `---` 但缺少 closing delimiter，会按“无有效 frontmatter”处理，在文件头新增一段完整 frontmatter。
- 该命令只负责补属性，不负责打开 Query File Defaults 说明文档或 UI。

## Phase 5.10 验收

- 无 frontmatter 的 Markdown 文件可以插入完整 `TQ_*` 属性块。
- 已有 frontmatter 的文件只补缺失属性。
- 已有 `TQ_*` 值和普通 frontmatter 属性保持不变。
- 重复执行命令不会产生重复属性。
- `TQ_extra_instructions` 多行内容仍能被 Phase 5.3 的 Query File Defaults 读取逻辑使用。
- Phase 5.9/5.8/5.3 smoke 无回归。
