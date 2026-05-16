# Phase 5.7: Completion Core + Markdown Task Adapter

目标：把 Phase 5.6 的 form auto-suggest 抽成可复用核心，并让普通 Markdown task 行也能手动触发同一套建议。

状态：已实现第一版，手动测试步骤见 `PHASE_5_7_TEST.md`，headless smoke 见 `scripts/smoke_phase5_7.sh`。

## 范围

新增 `lua/obsidian-tasks/completion.lua`：

- 统一维护 status、priority、date、recurrence、id、depends_on、on_completion 建议。
- 提供 form context 和 Markdown task line context。
- 提供 native completion trigger 和 completion item 应用能力。

Form buffer 仍保留 Phase 5.6 行为：

- 自动补全。
- `<C-Space>` 手动触发。
- `<C-X><C-U>` 走 form 的 `completefunc`。

普通 Markdown buffer 新增手动入口：

```vim
:ObsidianTasksComplete
```

也提供 `<Plug>` mapping：

```vim
imap <C-Space> <Plug>(ObsidianTasksComplete)
nmap <leader>tc <Plug>(ObsidianTasksComplete)
```

插件默认不把普通 Markdown buffer 的补全绑定到常用键，也不自动弹出，避免和 `nvim-cmp`、LSP、buffer/path completion 抢 UI。

## Markdown Task Context

只在 Markdown checklist task 行生效：

```markdown
- [ ] Write report 📅 tom
- [ ] Weekly review 🔁 every w
- [ ] Blocked task ⛔ alpha-id, b
- [ ] New task id 🆔 
- [ ] Important task h
```

支持：

- `📅 tom` -> 插入 ISO 日期，例如 `2026-05-17`。
- `🔁 every w` -> `every week`。
- `⛔ alpha-id, b` -> 从 vault 中已有 task id 补 `beta-id`。
- `🆔 ` -> 建议轻量生成的 `task-YYYYMMDD` 和已有 id。
- task 行普通 token，如 `h` -> priority emoji，例如 `⏫`。
- `🏁 d` -> `delete`。

## API

```lua
local completion = require("obsidian-tasks.completion")

completion.suggest({
  context = "markdown",
  field = "due",
  base = "tom",
})

completion.markdown_context({
  buf = 0,
})
```

`edit.lua` 的 `suggest_field()`、`complete()` 和 `trigger_complete()` 仍可用，但底层已经调用 completion core。

## 已知限制

- 还没有注册 `nvim-cmp` source。
- Markdown buffer 里只提供手动入口，不做自动弹窗。
- Markdown task 行的 field detection 是轻量启发式：优先识别光标前最近的 Tasks emoji metadata。
- Date completion 在 Markdown task 行中插入 ISO 日期；form buffer 中仍插入自然表达式并在保存时正规化。

## Phase 5.7 验收

- Form auto-suggest 行为不退化。
- 普通 task 行 `📅 tom` 能补 ISO due date。
- 普通 task 行 `🔁 every w` 能补 recurrence snippet。
- 普通 task 行 `⛔ alpha-id, b` 能补已有 dependency id。
- 普通 task 行 `h` 能补 priority emoji。
- 普通 Markdown 段落不会产生 task completion context。
