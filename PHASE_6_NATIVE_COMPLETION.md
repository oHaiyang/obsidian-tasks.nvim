# Phase 6 Native Completion Adapter

目标：给不使用 `nvim-cmp` 的 Neovim 原生补全用户提供一套 opt-in adapter，让普通 Markdown task 行可以使用 Obsidian Tasks 的 priority、date、recurrence、id、dependsOn 等补全。

这个小 phase 独立于 Phase 6.6。Phase 6.6 仍然保留给更完整的 task search suggestions 和 auto-suggest polish。

## 背景

Phase 5.7 已经提供了 completion core 和普通 Markdown task 行手动补全：

```vim
:ObsidianTasksComplete
```

Phase 5.8 已经提供了可选 `nvim-cmp` source。

但如果用户迁移到 Neovim 原生补全，且全局设置：

```lua
vim.o.autocomplete = false
```

那么非 LSP 的 `completefunc` 不会自动弹出。需要插件主动提供：

- buffer-local `completefunc`，支持 `<C-x><C-u>`。
- 手动 keymap。
- 精准 auto trigger，避免普通 Markdown 文本里乱弹。

## 配置

```lua
require("obsidian-tasks").setup({
  vault_path = "~/Notes",
  global_filter = "#task",
  completion = {
    native = {
      enabled = true,

      -- 为 markdown buffer 设置 completefunc，支持 <C-x><C-u>
      completefunc = true,

      -- 可设 false 不绑定
      keymap = "<M-Space>",

      auto_trigger = {
        enabled = true,

        -- 输入 📅/🔁/⛔/🆔 等 metadata symbol 后自动弹
        metadata_symbols = true,

        -- 输入 h/m/l 等 priority 前缀后自动弹；默认 false，避免 task 描述中误触发
        priority_prefix = false,
      },
    },
  },
})
```

兼容 camelCase：

```lua
autoTrigger = {
  metadataSymbols = true,
  priorityPrefix = true,
}
```

## 行为

启用后，插件会 attach 到 `markdown` / `md` buffer：

- 设置 `completefunc = v:lua.obsidian_tasks_native_complete`。
- 绑定 `keymap`，默认 `<M-Space>`。
- 可选 `InsertCharPre` 监听 metadata emoji，并在字符插入后自动触发补全。
- 可选 `TextChangedI` 监听 priority 前缀。

补全只在 Markdown task item 行生效。普通段落不会返回 items。

Markdown task 行示例：

```markdown
- [ ] #task Finish draft h
- [ ] #task Finish draft 📅 tom
- [ ] #task Repeat 🔁 every w
- [ ] #task Blocked ⛔ alpha, b
```

## 触发策略

### 手动触发

在 task 行上按：

```vim
<M-Space>
```

或者使用原生 `completefunc`：

```vim
<C-x><C-u>
```

### Metadata emoji 自动触发

当 `auto_trigger.metadata_symbols = true` 时，输入这些 symbol 后自动弹：

```text
➕ 🛫 ⏳ 📅 ✅ ❌ 🔁 🏁 🆔 ⛔
```

比如输入：

```markdown
- [ ] #task Due 📅
```

会弹出 `today`、`tomorrow`、`+7` 等候选，并在 Markdown task 行中插入 ISO 日期。

### Priority 前缀自动触发

当 `auto_trigger.priority_prefix = true` 时，只在 task 行且当前 token 是这些前缀时自动弹：

```text
h hi hig high highest
m me med medium
l lo low lowest
```

如果当前行已经有 priority emoji，则不会再次触发。

Priority 前缀不要求出现在所有 metadata 之前。比如已有 due date 后继续输入 `h`：

```markdown
- [ ] #task Follow up 📅 2026-05-23 h
```

仍会触发 priority 候选。但如果 `h` 是某个 metadata emoji 后的第一个值 token，例如：

```markdown
- [ ] #task Due 📅 h
```

则按 date value 处理，不触发 priority。

这个选项默认关闭，因为 task 描述中也可能自然输入 `home`、`handle`、`low level` 等文本。

## 已实现

- 新增 `lua/obsidian-tasks/completion/native.lua`。
- `setup({ completion = { native = true } })` 可启用默认配置。
- `setup({ completion = { native = { enabled = true } } })` 可启用详细配置。
- 自动 attach 当前和后续 Markdown buffers。
- 不接管 LSP `omnifunc`，不影响 `<C-x><C-o>`。
- 不依赖 `nvim-cmp`。

## 验收

- Markdown task buffer 设置了 `completefunc`。
- `<C-x><C-u>` 能返回 priority/date/recurrence/dependency items。
- 默认 `<M-Space>` 可手动触发。
- 普通 Markdown 段落不返回 items。
- metadata emoji auto trigger 可识别 trigger characters。
- priority auto trigger 默认关闭，开启后只在 task 行、无已有 priority emoji、当前 token 前缀匹配且不是 metadata 的第一个值 token 时触发。
- Phase 5.7/5.8 completion smoke 无回归。
