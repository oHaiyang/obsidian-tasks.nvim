# Phase 5.6 手动测试步骤

这份文档用于手动验证 edit form auto-suggest MVP。

## 1. 准备 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-6-vault
rm -rf "$VAULT"
mkdir -p "$VAULT"
cat > "$VAULT/Form.md" <<'EOF'
# Form
- [ ] #task Existing dependency 🆔 alpha-id
- [ ] #task Another dependency 🆔 beta-id
- [ ] #task Target task
EOF
```

## 2. 准备 init.lua

```sh
cat > /private/tmp/obsidian-tasks-phase5-6-init.lua <<'EOF'
vim.opt.rtp:append("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

require("obsidian-tasks").setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase5-6-vault",
  global_filter = "#task",
  today = "2026-05-16",
  auto_suggest_in_editor = true,
  auto_suggest_min_chars = 0,
  auto_suggest_max_items = 20,
  status_settings = {
    { symbol = " ", name = "Todo", type = "TODO", next_symbol = "/" },
    { symbol = "/", name = "In Progress", type = "IN_PROGRESS", next_symbol = "x" },
    { symbol = "?", name = "Waiting", type = "ON_HOLD", next_symbol = "x" },
    { symbol = "x", name = "Done", type = "DONE", next_symbol = " " },
  },
})
EOF
```

## 3. 打开 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-6-init.lua /private/tmp/obsidian-tasks-nvim-phase5-6-vault/Form.md
```

把光标放到 `Target task` 那一行，执行：

```vim
:ObsidianTasksEdit
```

## 4. 测试字段补全

在 form buffer 中进入 insert mode：

- `status: W` 后应建议 `Waiting`。
- `priority: h` 后应建议 `highest` 和 `high`。
- `due: tom` 后应建议 `tomorrow`。
- `recurrence: every w` 后应建议 `every week` / `every weekday`。
- `id: task` 后应建议一个 `task-20260516` 形式的 id。
- `depends_on: a` 后应建议 `alpha-id`。
- `depends_on: alpha-id, b` 后应建议 `beta-id`。
- `on_completion: d` 后应建议 `delete`。

如果自动弹窗没有出现，可以按：

```vim
<C-Space>
```

或使用 Neovim 原生补全：

```vim
<C-X><C-U>
```

## 5. 测试保存

设置示例：

```text
status: Waiting
priority: high
due: tomorrow
recurrence: every week
id: task-20260516
depends_on: alpha-id, beta-id
on_completion: keep
```

按 `<C-S>` 保存后，源文件应写成类似：

```text
- [?] #task Target task ⏫ 🔁 every week 🏁 keep 📅 2026-05-17 🆔 task-20260516 ⛔ alpha-id, beta-id
```

## 6. 测试 smoke

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_6.sh
```

预期命令退出码为 0。

## 7. 已知限制

- 目前是 form buffer 内置补全，不是 `nvim-cmp` source。
- `depends_on` 补已有 task id，不提供任务搜索 UI。
- recurrence 保存后的实际推进仍受当前 recurrence parser 能力限制。
