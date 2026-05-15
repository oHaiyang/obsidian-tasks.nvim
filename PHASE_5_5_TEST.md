# Phase 5.5 手动测试步骤

这份文档用于手动验证 edit/create form 的自然日期解析和轻量 picker。

## 1. 准备临时测试 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-5-vault
rm -rf "$VAULT"
mkdir -p "$VAULT"

cat > "$VAULT/Form.md" <<'EOF'
# Form

- [ ] #task Alpha 📅 2026-05-20
EOF
```

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase5-5-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

require("obsidian-tasks").setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase5-5-vault",
  global_filter = "#task",
  today = "2026-05-16",
  set_created_date = true,
})
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-5-init.lua /private/tmp/obsidian-tasks-nvim-phase5-5-vault/Form.md
```

## 4. 测试编辑表单自然日期

把光标放在 Alpha 任务行，执行：

```vim
:ObsidianTasksEdit
```

修改字段：

```text
status: In Progress
priority: medium
created: 6 oct
start: 2 weeks
scheduled: +3
due: tomorrow
```

保存：

```vim
<C-S>
```

预期源任务包含：

```markdown
[/]
🔼
➕ 2026-10-06
🛫 2026-05-30
⏳ 2026-05-19
📅 2026-05-17
```

## 5. 测试非法日期阻止保存

执行：

```vim
:ObsidianTasksCreate
```

填入：

```text
description: Created with bad date #task
due: not-a-date
```

保存时预期提示 `Invalid due date`，form buffer 保留，源文件不应新增该任务。

把 `due` 改成：

```text
due: oct 7
```

再次保存，预期新增任务包含：

```markdown
➕ 2026-05-16
📅 2026-10-07
```

## 6. 测试 status/date picker

在 form buffer 中：

- 按 `gs`：选择 status，预期写入 `status:` 字段。
- 把光标放到 `due:` 行，按 `gd`：选择常用日期，预期写入 `due:` 字段。

## 7. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_5.sh
```

预期无错误退出。

## 8. 已知限制

- 还没有 continuous auto-suggest popup。
- 还没有完整 calendar picker。
- 未写年份的 named month 日期使用当前年份。
