# Phase 5.7 手动测试步骤

这份文档用于手动验证 completion core 和普通 Markdown task 行补全。

## 1. 准备 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-7-vault
rm -rf "$VAULT"
mkdir -p "$VAULT"
cat > "$VAULT/Complete.md" <<'EOF'
# Complete
- [ ] #task Existing dependency 🆔 alpha-id
- [ ] #task Another dependency 🆔 beta-id
- [ ] #task Due field 📅 tom
- [ ] #task Recurring field 🔁 every w
- [ ] #task Depends field ⛔ alpha-id, b
- [ ] #task Id field 🆔 
- [ ] #task Priority field h
Plain paragraph 📅 tom
EOF
```

## 2. 准备 init.lua

```sh
cat > /private/tmp/obsidian-tasks-phase5-7-init.lua <<'EOF'
vim.opt.rtp:append("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

require("obsidian-tasks").setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase5-7-vault",
  global_filter = "#task",
  today = "2026-05-16",
})

imap <C-Space> <Plug>(ObsidianTasksComplete)
nmap <leader>tc <Plug>(ObsidianTasksComplete)
EOF
```

## 3. 打开 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-7-init.lua /private/tmp/obsidian-tasks-nvim-phase5-7-vault/Complete.md
```

## 4. 测试 Markdown task 行补全

在 insert mode 中把光标放到对应位置，按 `<C-Space>`：

- `📅 tom` 应建议并插入 `2026-05-17`。
- `🔁 every w` 应建议 `every week`。
- `⛔ alpha-id, b` 应建议 `beta-id`。
- `🆔 ` 应建议 `task-20260516`。
- `Priority field h` 应建议 priority emoji，例如 `⏫`。

Normal mode 也可执行：

```vim
:ObsidianTasksComplete
```

这会用 `vim.ui.select()` 选择一条建议并写回当前行。

## 5. 确认不会打扰普通 Markdown

把光标放到：

```markdown
Plain paragraph 📅 tom
```

执行：

```vim
:ObsidianTasksComplete
```

预期提示当前行不是 Markdown task field，不应修改普通段落。

## 6. 测试 smoke

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_7.sh
```

预期命令退出码为 0。

## 7. 已知限制

- 还没有 `nvim-cmp` source。
- 普通 Markdown buffer 不自动弹出补全，避免和用户已有补全框架冲突。
- Markdown task context 是轻量启发式，复杂行内 metadata 场景后续继续打磨。
