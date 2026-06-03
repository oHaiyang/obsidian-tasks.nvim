# Phase 6.3: Show Tree + Sub-Items

目标：实现原版 Obsidian Tasks 的 `show tree` / `hide tree` 结果展示，并支持 `exclude sub-items` filter。

## 原版依据

原版实现和文档位于：

- `../obsidian-tasks/docs/Queries/Layout.md`
- `../obsidian-tasks/src/Task/ListItem.ts`
- `../obsidian-tasks/src/Renderer/QueryResultsRendererBase.ts`
- `../obsidian-tasks/src/Query/Filter/ExcludeSubItemsField.ts`

原版当前行为：

- `tree` 默认隐藏，需要 query 中显式写 `show tree`。
- `show tree` 会显示命中 task 的 nested tasks 和 list items。
- 子 task / list item 即使不匹配 query，也会作为上下文显示。
- 排序主要影响最外层命中 task；children 按源文件顺序显示。
- `exclude sub-items` 是独立 filter，用于排除缩进的子任务。

## 已实现

- scanner 扫描 Markdown task 时，同时记录普通 list item tree。
- 每个命中 task 关联其 `list_item` / `listItem`。
- list item 记录：
  - `original_markdown`
  - `indentation`
  - `list_marker`
  - `status_symbol`
  - `description`
  - `parent`
  - `children`
- query parser 支持 `exclude sub-items`。
- query matcher 按原版规则处理 blockquote/callout 顶层 task：
  - `- [ ] Task` 保留。
  - `  - [ ] Subtask` 排除。
  - `> - [ ] Task` 保留。
  - `>>  - [ ] Subtask` 排除。
- display 支持 `show tree`：
  - 命中 task 行保留数字索引，可继续 toggle/edit/postpone/jump/save。
  - 未命中的 child task 和普通 list item 只作为上下文显示，不写入 `task_index_map`。
  - 多个命中 task 共享父子关系时，同一 group 内避免重复显示。
- `hide tree` 或默认状态仍使用扁平结果。
- 缩进的 indexed task display line 可被 `parse_display_line()` 解析。

## 当前边界

- 第一版不主动补齐命中子任务的祖先上下文；这与原版当前 renderer 更接近。
- child task 如果不是 query 命中项，只作为上下文显示，不能在 result buffer 中直接编辑。
- `show tree` 下 group 之间不去重；和原版一样，每个 group 独立渲染。
- blockquote/callout 的 tree indentation 做了轻量处理，复杂混排后续再 polish。

## Phase 6.3 验收

- 默认查询仍是扁平显示。
- `show tree` 显示命中 task 的 child list items 和 child tasks。
- `hide tree` 显式关闭 tree。
- child context 行不进入 `core.task_index_map`。
- 命中的 nested task 行有唯一 index，`gd/gf` 和状态保存仍能依赖 index map。
- `exclude sub-items` 排除普通缩进子任务。
- `exclude sub-items` 保留 blockquote/callout 中的顶层 task。

## 自动测试

```sh
sh scripts/smoke_phase6_3.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase4.sh
sh scripts/smoke_phase2.sh
```
