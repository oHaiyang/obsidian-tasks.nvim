# Phase 6.6 手动测试步骤

这份文档用于手动验证 task search suggestions、dependency 补全和 completion adapter 兼容性。

## 1. 准备任务

在 vault 中新建一个 Markdown 文件，例如 `Search Complete Test.md`：

```markdown
- [ ] #task Alpha prerequisite 🆔 alpha-id
- [ ] #task Beta blocker 🆔 beta-id
- [ ] #task Gamma has no id
- [ ] #task Current depends item 🆔 current-id ⛔ b
```

确认配置加载了本地插件：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  completion = {
    native = {
      enabled = true,
      completefunc = true,
      keymap = "<M-Space>",
      auto_trigger = {
        enabled = true,
        metadata_symbols = true,
        date_keywords = true,
        date_values = true,
      },
    },
  },
})
```

如果你使用 `nvim-cmp`，也可以启用：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  completion = {
    cmp = true,
  },
})
```

## 2. 普通 Markdown task 行补 dependency

把光标放到最后一行的 `b` 后面：

```markdown
- [ ] #task Current depends item 🆔 current-id ⛔ b
```

在 insert mode 使用你配置的补全入口，例如：

```vim
<M-Space>
```

或者原生 completefunc：

```vim
<C-x><C-u>
```

预期：

- 候选里有 `beta-id`。
- 候选展示包含 `Beta blocker`、文件名和行号。
- 候选里不应该出现 `current-id`。
- 确认 `beta-id` 后，当前行变成：

```markdown
- [ ] #task Current depends item 🆔 current-id ⛔ beta-id
```

## 3. 按描述搜索任务

把当前行改成：

```markdown
- [ ] #task Current depends item 🆔 current-id ⛔ Alpha
```

触发补全。

预期可以看到并选择 `alpha-id`，因为候选支持按 task description 前缀匹配。

## 4. Form buffer 补 dependency

把光标放到最后一条任务上：

```vim
:ObsidianTasksEdit
```

移动到 `depends_on:` 字段，输入：

```text
Alpha
```

触发 form 补全：

```vim
<C-Space>
```

或：

```vim
<C-x><C-u>
```

预期：

- 候选里有 `alpha-id`。
- 候选里不出现当前任务自己的 `current-id`。
- 确认后 `depends_on:` 字段写入 id 文本。

## 5. 无 id 任务边界

`Gamma has no id` 不应该作为普通 `depends_on` completion 的可插入候选出现。

如果需要依赖这条无 id 任务，使用：

```vim
:ObsidianTasksAddDependency
```

或在 form buffer 中按：

```vim
gD
```

预期插件会选择目标任务，必要时自动给目标任务补 `🆔 id`，然后把 id 添加到当前任务。

## 6. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase6_6.sh
```

建议再跑：

```sh
sh scripts/smoke_phase5_8.sh
sh scripts/smoke_phase5_7.sh
sh scripts/smoke_phase5_6.sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase6_native_completion.sh
```
