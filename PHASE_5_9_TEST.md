# Phase 5.9 手动测试步骤

这份文档用于手动验证 dependency editor 和 better date picker。

## 1. 准备 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-9-vault
rm -rf "$VAULT"
mkdir -p "$VAULT"
cat > "$VAULT/Deps.md" <<'EOF'
# Dependencies
- [ ] #task Current task
- [ ] #task Needs generated id
- [ ] #task Existing id 🆔 existing-id
- [ ] #task Date task
EOF
```

## 2. 准备 init.lua

```sh
cat > /private/tmp/obsidian-tasks-phase5-9-init.lua <<'EOF'
vim.opt.rtp:append("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

require("obsidian-tasks").setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase5-9-vault",
  global_filter = "#task",
  today = "2026-05-16",
})

nmap <leader>td <Plug>(ObsidianTasksAddDependency)
nmap <leader>tt <Plug>(ObsidianTasksPickDate)
EOF
```

## 3. 打开 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-9-init.lua /private/tmp/obsidian-tasks-nvim-phase5-9-vault/Deps.md
```

## 4. 测试普通 task 行依赖选择

把光标放在 `Current task` 行，执行：

```vim
:ObsidianTasksAddDependency
```

选择 `Needs generated id`。

预期：

- `Needs generated id` 行新增 `🆔 task-...`。
- `Current task` 行新增 `⛔ task-...`。

再次执行并选择 `Existing id`：

- `Current task` 行会追加 `existing-id`。
- 重复选择同一个依赖不会重复写入。

## 5. 测试 form 依赖选择

把光标放在 `Current task` 行，执行：

```vim
:ObsidianTasksEdit
```

在 form buffer 中按：

```vim
gD
```

选择一个任务后，`depends_on:` 字段应追加对应 id。

## 6. 测试 form 日期选择

在 form buffer 中移动到 `due:` 行，按：

```vim
gd
```

依次测试：

- Tomorrow
- Next week
- Custom input
- Clear

非法 custom input 应提示错误并保留原值。

## 7. 测试普通 task 行日期选择

把光标放到 `Date task` 行，执行：

```vim
:ObsidianTasksPickDate due
```

选择 Tomorrow 后，当前行应新增：

```text
📅 2026-05-17
```

也可以测试：

```vim
:ObsidianTasksPickDate scheduled
:ObsidianTasksPickDate start
```

## 8. 测试 smoke

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_9.sh
```

预期命令退出码为 0。
