# Phase 5.4 手动测试步骤

这份文档用于手动验证 result buffer 和 inline preview 的 layout directives。

## 1. 准备临时测试 vault

````sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-4-vault
rm -rf "$VAULT"
mkdir -p "$VAULT"

cat > "$VAULT/Layout.md" <<'EOF'
# Layout

```tasks
# name: Preview Compact
# id: preview-compact
hide task count
hide backlink
hide tags
description includes Preview
```

- [ ] #task Alpha #work ⏫ 📅 2026-05-20 🆔 alpha
- [ ] #task Beta #home 🔼 📅 2026-05-21 🆔 beta
- [ ] #task Preview #preview 📅 2026-05-22
EOF
````

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase5-4-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

require("obsidian-tasks").setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase5-4-vault",
  global_filter = "#task",
  queries = {
    compact = [[
description includes Alpha
hide task count
hide backlink
hide priority
hide tags
hide due date
hide id
]],
    visible = [[
description includes Beta
show task count
show backlink
show priority
show tags
show due date
show id
]],
  },
})
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-4-init.lua /private/tmp/obsidian-tasks-nvim-phase5-4-vault/Layout.md
```

## 4. 测试 hide directives

```vim
:ObsidianTasks compact
```

预期：

- Header 不显示 `Showing ... tasks`。
- Alpha 行不显示 `[[...#L...]]`。
- Alpha 行不显示 `[HIGH]`、`⏫`。
- Alpha 行不显示 `#task`、`#work`。
- Alpha 行不显示 `📅 2026-05-20`。
- Alpha 行不显示 `🆔 alpha`。

在 Alpha 行按：

```vim
<space>
<c-s>
```

预期：

- result line 能切换到 `[x]`。
- 源文件中的 Alpha task 被保存为完成状态。
- 即使 backlink 被隐藏，保存仍然成功。

## 5. 测试 show directives

```vim
:ObsidianTasks visible
```

预期：

- Header 显示 `Showing 1 tasks`。
- Beta 行显示 backlink。
- Beta 行显示 `[MEDIUM]`。
- Beta 行显示 `#task`、`#home`。
- Beta 行显示 `📅 2026-05-21`。
- Beta 行显示 `🆔 beta`。

## 6. 测试 preview directives

回到 `Layout.md`，执行：

```vim
:ObsidianTasksPreviewToggle
```

预期 preview：

- 不显示 `Showing ...`。
- 不显示 `#L...` 文件位置。
- 不显示 `#task` 和 `#preview`。
- 仍显示 `Preview` 任务描述。

## 7. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_4.sh
```

预期无错误退出。

## 8. 已知限制

- `show tree` / `hide tree` 暂未实现树形子项展示。
- `show toolbar` / `hide toolbar` 暂未实现工具栏。
- `show urgency` 暂未实现 urgency 计算。
