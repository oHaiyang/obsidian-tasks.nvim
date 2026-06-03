# Phase 6.4: Toolbar + Result View Polish

目标：补齐原版 Obsidian Tasks 查询结果 toolbar 的 Neovim 等价能力，让结果 buffer 可以临时过滤和复制当前结果。

## 原版依据

原版实现和文档位于：

- `../obsidian-tasks/docs/Queries/Layout.md`
- `../obsidian-tasks/src/Layout/QueryLayoutOptions.ts`
- `../obsidian-tasks/src/Layout/QueryLayout.ts`
- `../obsidian-tasks/src/Renderer/HtmlQueryResultsRenderer.ts`

原版 toolbar 能：

- 临时按 description 过滤当前结果。
- 复制当前查询结果为 Markdown。
- 遵守 `show toolbar` / `hide toolbar`。

## 已实现

- `show toolbar` / 默认状态会在 result header 显示：

```text
Toolbar: f filter description  c clear filter  y copy markdown  Y copy with backlinks
```

- `hide toolbar` 会隐藏 toolbar 行，并不绑定 `f` / `c` / `y` / `Y` toolbar keymaps。
- `f` 输入临时 description filter，只过滤当前 result buffer，不修改 query source。
- `c` 清空临时 filter。
- `y` 复制当前可见结果为 Markdown，不包含 result index 和 backlink。
- `Y` 复制当前可见结果为 Markdown，并给 indexed task 行补 source backlink。
- copy 会保留 group headings 和 `show tree` 下的 child context lines。
- toolbar filter 会更新 `core.task_index_map`，因此过滤后可见 indexed task 仍能 toggle/edit/postpone/jump/save。
- 如果 result buffer 有未保存修改，toolbar filter 会拒绝重画并提示先保存，避免丢失用户在结果 buffer 中做的状态改动。

## 当前边界

- 临时 filter 只匹配 task description，不匹配文件名、heading、metadata 或 child context line。
- filter 会重新渲染当前 result buffer；未保存改动需要先保存。
- copy 使用当前 result buffer 的可见内容作为基础，不复制 header 和 toolbar 行。
- Neovim 版没有实现原版 HTML toolbar 的按钮样式，只提供 result buffer keymaps。

## Phase 6.4 验收

- 默认和 `show toolbar` 显示 toolbar 行。
- `hide toolbar` 隐藏 toolbar 行。
- `f` / `display.set_toolbar_filter()` 可缩小当前结果。
- `c` / `display.clear_toolbar_filter()` 可恢复当前结果。
- filter 后 `task_index_map` 对应可见 indexed task。
- `y` / `display.copy_markdown({ include_backlinks = false })` 写入 unnamed register，去掉 index/backlink。
- `Y` / `display.copy_markdown({ include_backlinks = true })` 写入 unnamed register，并包含 source backlink。
- copy 遵守 `show tree`，包含 child context lines。

## 自动测试

```sh
sh scripts/smoke_phase6_4.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase6_3.sh
```
