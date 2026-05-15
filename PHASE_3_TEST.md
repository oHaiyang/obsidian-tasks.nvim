# Phase 3 手动测试步骤

这份文档用于手动验证 Phase 3 的 named `tasks` query block、query registry、`RunBlock` 和只读 inline preview。

测试目标：

- vault 中的 `tasks` code block 可以被自动发现。
- `# name:` / `# id:` 能成为 query 的显示名和稳定 id。
- `:ObsidianTasks` / picker 可以打开 block query。
- 结果 buffer 中 `gq` 可以跳回 query block。
- `:ObsidianTasksRunBlock` 可以运行光标所在的 query block。
- `:ObsidianTasksRefreshQueries` 可以重新扫描 query block。
- inline preview 只用 virtual lines 展示摘要，不修改 Markdown 文件。

## 1. 准备临时测试 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase3-vault
rm -rf "$VAULT"
mkdir -p "$VAULT/Projects" "$VAULT/Daily"

cat > "$VAULT/Dashboard.md" <<'EOF'
# Dashboard

```tasks
# name: Due soon
# id: due-soon
not done
due on or before 2026-05-20
sort by due
group by filename
```

~~~tasks
# name: Recurring tasks
# id: recurring-tasks
is recurring
sort by due
~~~

```tasks
# name: No ID Query
not done
heading includes Daily
```
EOF

cat > "$VAULT/Projects/Project A.md" <<'EOF'
# Project A

- [ ] #task Write query block scanner 📅 2026-05-15
- [ ] #task Future project task 📅 2026-06-01
- [x] #task Done old task ✅ 2026-05-12 📅 2026-05-13
EOF

cat > "$VAULT/Daily/2026-05-15.md" <<'EOF'
# Daily

- [ ] #task Daily inbox item 📅 2026-05-16
- [ ] #task Recurring daily item 🔁 every week 📅 2026-05-20
EOF
```

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase3-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

local tasks = require("obsidian-tasks")

tasks.setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase3-vault",
  global_filter = "#task",
  default_query = "due-soon",
  queries = {
    inbox = [[
not done
sort by due
]],
  },
})

vim.keymap.set("n", "<leader>to", tasks.open, { desc = "Obsidian Tasks: open panel" })
vim.keymap.set("n", "<leader>tr", tasks.run_query_at_cursor, { desc = "Obsidian Tasks: run block" })
vim.keymap.set("n", "<leader>tp", tasks.preview_toggle, { desc = "Obsidian Tasks: preview toggle" })
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase3-init.lua /private/tmp/obsidian-tasks-nvim-phase3-vault/Dashboard.md
```

确认命令存在：

```vim
:command ObsidianTasks
:command ObsidianTasksRefreshQueries
:command ObsidianTasksRunBlock
:command ObsidianTasksPreviewToggle
```

## 4. 测试 query block 自动发现

执行：

```vim
:ObsidianTasksRefreshQueries
```

预期通知：

```text
Refreshed 3 tasks query block(s)
```

也可以直接检查 source：

```vim
:lua print(vim.inspect(require("obsidian-tasks.query_registry").get_sources()))
```

预期能看到：

- `config: inbox`
- `block: due-soon`
- `block: recurring-tasks`
- `block: no-id-query`

## 5. 测试默认打开 block query

执行：

```vim
:ObsidianTasks
```

预期：

- 打开 `Tasks: Due soon`。
- 只出现 `2026-05-20` 之前的未完成任务。
- 不出现 `Future project task`。
- 不出现 `Done old task`。

## 6. 测试 picker 中选择 block query

在结果 buffer 中按：

```vim
o
```

预期 picker 中能看到 config query 和 block query，例如：

```text
inbox                        config
Due soon                     block    Dashboard.md#L3
Recurring tasks              block    Dashboard.md#L12
No ID Query                  block    Dashboard.md#L19
```

选择 `Recurring tasks`。

预期：

- 结果标题变成 `Tasks: Recurring tasks`。
- 只显示 recurring task。

## 7. 测试 gq 跳回 query source

在结果 buffer 中执行：

```vim
gq
```

预期：

- 打开 `/private/tmp/obsidian-tasks-nvim-phase3-vault/Dashboard.md`。
- 光标跳到对应 `tasks` code block 的起始 fence 行。

## 8. 测试直接打开指定 block query

```vim
:ObsidianTasks due-soon
:ObsidianTasks recurring-tasks
:ObsidianTasks no-id-query
```

预期都能打开对应 query。

如果以后出现同名冲突，可以用 picker 中显示的 source 来区分；当前第一版仍优先按 config query、再按 block query 匹配。

## 9. 测试 RunBlock

回到 `Dashboard.md`，把光标放在第一个 `tasks` block 内任意一行，执行：

```vim
:ObsidianTasksRunBlock
```

预期打开 `Tasks: Due soon`。

再把光标放到非 `tasks` block 的普通文本行，执行：

```vim
:ObsidianTasksRunBlock
```

预期收到提示：

```text
cursor is not inside a tasks query block
```

## 10. 测试 pinned block query

```vim
:ObsidianTasks! due-soon
:ObsidianTasks! recurring-tasks
```

预期：

- 两个 pinned result buffer 可以同时存在。
- buffer 名类似 `obsidian-tasks://block_due-soon_...`。

## 11. 测试 inline preview

在 `Dashboard.md` 执行：

```vim
:ObsidianTasksPreviewToggle
```

预期：

- 每个 `tasks` block 后方显示只读 virtual lines。
- 第一行类似 `Tasks preview: Showing 2 of 2`。
- Markdown 文件内容没有被修改。

刷新 preview：

```vim
:ObsidianTasksPreviewRefresh
```

关闭 preview：

```vim
:ObsidianTasksPreviewToggle
```

## 12. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase3.sh
```

预期无错误退出。

## 13. 本阶段已知限制

- `tasks` block 只作为 query definition，不做 Obsidian 那种原地替换渲染。
- inline preview 是只读摘要，不支持在 preview 中 toggle/save/edit。
- query registry 是轻量缓存，新增或删除 block 后需要 `:ObsidianTasksRefreshQueries`。
- Query File Defaults、presets、placeholders 暂未实现。
- Boolean / regex / function query 暂未实现。
