# Phase 6 Native Completion Adapter 手动测试步骤

这份文档用于手动验证 Neovim 原生补全 adapter。

## 1. 配置插件

```lua
require("obsidian-tasks").setup({
  vault_path = "~/Notes",
  global_filter = "#task",
  today = "2026-05-22",
  completion = {
    native = {
      enabled = true,
      completefunc = true,
      keymap = "<M-Space>",
      auto_trigger = {
        enabled = true,
        metadata_symbols = true,
        priority_prefix = true,
      },
    },
  },
})
```

如果觉得 priority 自动触发太吵，可以先关掉：

```lua
priority_prefix = false
```

## 2. 检查 completefunc

打开 Markdown 文件，执行：

```vim
:setlocal completefunc?
```

预期：

```text
completefunc=v:lua.obsidian_tasks_native_complete
```

## 3. 手动触发 priority

输入：

```markdown
- [ ] #task Priority h
```

在 `h` 后按：

```vim
<M-Space>
```

预期出现 priority 候选：

- `highest 🔺`
- `high ⏫`

选择 `high ⏫` 后，任务行变成：

```markdown
- [ ] #task Priority ⏫
```

## 4. 手动触发 date

输入：

```markdown
- [ ] #task Due 📅 tom
```

在 `tom` 后按：

```vim
<M-Space>
```

预期出现日期候选，并插入 ISO 日期，例如在 `today = 2026-05-22` 时：

```markdown
- [ ] #task Due 📅 2026-05-23
```

## 5. 原生 completefunc

在 task 行上也可以按：

```vim
<C-x><C-u>
```

预期和 `<M-Space>` 一样返回 Obsidian Tasks 候选。

注意：`<C-x><C-o>` 仍然留给 LSP completion，例如 `markdown_oxide`。

## 6. Metadata emoji 自动触发

确认配置中：

```lua
metadata_symbols = true
```

输入：

```markdown
- [ ] #task Due 📅
```

预期输入 `📅` 后自动弹日期候选。

## 7. Priority 前缀自动触发

确认配置中：

```lua
priority_prefix = true
```

输入：

```markdown
- [ ] #task Priority h
```

预期输入 `h` 后自动弹 priority 候选。

普通 Markdown 段落里输入 `h` 不应弹。

如果 task 行已经存在 priority emoji：

```markdown
- [ ] #task Already high ⏫ h
```

再输入 `h` 不应自动弹 priority 候选。

已有 metadata 值之后可以继续触发 priority：

```markdown
- [ ] #task Follow up 📅 2026-05-23 h
```

预期输入最后的 `h` 后自动弹 priority 候选。

metadata emoji 后的第一个值 token 不应被当成 priority：

```markdown
- [ ] #task Due 📅 h
```

预期这里不弹 priority 候选。

## 8. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase6_native_completion.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_7.sh
sh scripts/smoke_phase5_8.sh
```
