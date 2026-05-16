# Phase 5.6: Edit Form Auto-Suggest MVP

目标：补上原版 Obsidian Tasks 编辑弹窗里的自动建议体验。Neovim 版本先在 task form buffer 内提供轻量补全源，不依赖 `nvim-cmp` 等外部插件。

状态：已实现第一版，手动测试步骤见 `PHASE_5_6_TEST.md`，headless smoke 见 `scripts/smoke_phase5_6.sh`。

## 范围

Phase 5.6 覆盖 form buffer 中这些字段：

- `status`：按 status registry 建议状态名和 status symbol。
- `priority`：建议 `highest`、`high`、`medium`、`none`、`low`、`lowest`。
- date fields：建议 `today`、`tomorrow`、`+7`、`1 week`、`next month` 等 Phase 5.5 已支持的自然日期。
- `recurrence`：建议常用 recurrence snippets。
- `id`：建议一个轻量生成的 task id，并列出现有 id。
- `depends_on`：从 vault 中已有 task id 补全依赖。
- `on_completion`：建议 `keep`、`delete`。

## 交互

在 `:ObsidianTasksEdit` 或 `:ObsidianTasksCreate` 打开的 form buffer 里：

- insert mode 输入受支持字段时，会自动弹出补全菜单。
- insert mode 按 `<C-Space>` 手动触发补全。
- 也可以使用原生 completefunc：`<C-X><C-U>`。

Form header 会提示：

```text
# Shortcuts: gs pick status, gd pick date, <C-Space>/<C-X><C-U> suggest, q close.
```

## 配置

```lua
require("obsidian-tasks").setup({
  auto_suggest_in_editor = true,
  auto_suggest_min_chars = 0,
  auto_suggest_max_items = 20,
})
```

兼容 camelCase：

- `autoSuggestInEditor`
- `autoSuggestMinChars`
- `autoSuggestMaxItems`

`auto_suggest_in_editor = false` 会关闭 insert mode 自动触发和 `<C-Space>` 手动触发；`<C-X><C-U>` 仍可作为 Neovim 原生 completefunc 入口使用。

## 已知限制

- 还不是完整的外部 completion source。
- `depends_on` 只补已有 task id，不做任务搜索/选择器。
- `id` 的生成策略是轻量 MVP，还不是原版完整随机 ID 行为。
- recurrence 仍只提供常用 snippets，保存后的 recurrence 解析能力沿用 Phase 4 的基础规则。

## Phase 5.6 验收

- Form buffer 设置了 `completefunc`。
- `status`、`priority`、date、`recurrence`、`id`、`depends_on`、`on_completion` 都能返回建议项。
- `depends_on` 能从 vault task id 中补全。
- `auto_suggest_max_items` 能限制返回条数。
- Phase 5.5/5.4/5.3/5.2/5.1/5/4/3/2 smoke 无回归。
