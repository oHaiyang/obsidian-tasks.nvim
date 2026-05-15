# Phase 2 手动测试步骤

这份文档用于手动验证 Phase 2 的查询语言和 Tasks panel。

测试目标：

- `setup()` 支持 `queries` 和 `default_query`。
- 可以在任意 buffer 执行 `:ObsidianTasks` 打开任务面板。
- 支持 query filters、sort、group、limit。
- 支持 `:ObsidianTasks! name` 同时保留 pinned 查询结果。
- 查询结果中继续支持 toggle、save、refresh、jump。
- query 错误和空结果能显示在 buffer 中。

## 1. 准备临时测试 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase2-vault
rm -rf "$VAULT"
mkdir -p "$VAULT/Projects" "$VAULT/Daily"

cat > "$VAULT/Projects/Project A.md" <<'EOF'
# Project A

- [ ] #task Write query parser 🔼 📅 2026-05-15
- [ ] #task Add panel command ⏫ 📅 2026-05-18
- [x] #task Done old task ✅ 2026-05-12 📅 2026-05-13
- [ ] No global filter 📅 2026-05-14

## Later

- [ ] #task Future task 📅 2026-06-01
EOF

cat > "$VAULT/Daily/2026-05-14.md" <<'EOF'
# Daily

- [ ] #task Inbox item 📅 2026-05-14
- [ ] #task Scheduled item ⏳ 2026-05-16
- [ ] #task Started item 🛫 2026-05-13
- [ ] #task Recurring item 🔁 every week 📅 2026-05-20
- [ ] #task Task with dependency 🆔 phase2-a
- [ ] #task Depends on phase2-a ⛔ phase2-a
EOF
```

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase2-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

local tasks = require("obsidian-tasks")

tasks.setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase2-vault",
  global_filter = "#task",
  default_query = "due_soon",
  queries = {
    due_soon = [[
not done
due on or before 2026-05-20
sort by due
group by filename
limit 3
]],
    inbox = [[
not done
sort by due
group by filename
]],
    recurring = [[
is recurring
sort by due
]],
    dependencies = [[
has depends on
]],
    by_happens = [[
not done
has due date
sort by happens
group by happens
]],
  },
})

vim.keymap.set("n", "<leader>to", tasks.open, { desc = "Obsidian Tasks: open panel" })
vim.keymap.set("n", "<leader>tq", function()
  vim.cmd("ObsidianTasks")
end, { desc = "Obsidian Tasks: default query" })
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase2-init.lua /private/tmp/obsidian-tasks-nvim-phase2-vault/Projects/Project\ A.md
```

确认 config：

```vim
:lua print(vim.inspect(require("obsidian-tasks").config.queries))
```

预期能看到 `due_soon`、`inbox`、`recurring`、`dependencies`、`by_happens`。

确认命令：

```vim
:lua print(vim.inspect(vim.api.nvim_get_commands({}).ObsidianTasks ~= nil))
```

预期输出 `true`。如果这里是 `false`，说明当前 Neovim 没有加载到这个插件目录，或者临时 init 没有执行到 `tasks.setup()`。

## 4. 测试默认 Tasks panel

执行：

```vim
:ObsidianTasks
```

预期：

- 打开 `Tasks: due_soon`。
- 顶部显示类似 `Showing 3 of 5 tasks`。
- 只出现带 `#task` 的未完成任务。
- 不出现 `Done old task`。
- 不出现 `No global filter`。
- 不出现 `Future task`，因为它超过 `2026-05-20`。

## 5. 测试指定 query

```vim
:ObsidianTasks inbox
```

预期：

- 标题变为 `Tasks: inbox`。
- 会出现 `Future task`。
- 仍然不会出现 `Done old task` 和 `No global filter`。

## 6. 测试 pinned 多查询

```vim
:ObsidianTasks! due_soon
:ObsidianTasks! recurring
```

预期：

- 两个查询都可以保留成独立 buffer。
- buffer 名类似 `obsidian-tasks://due_soon` 和 `obsidian-tasks://recurring`。
- 你可以用 `:buffers` 查看。

## 7. 测试 query picker 和切换

在 Tasks panel 中按：

```vim
o
```

选择另一个 query。

再测试：

```vim
]q
[q
```

预期：

- `o` 能打开 query picker。
- `]q` / `[q` 能切换到下一个/上一个 config query。
- 结果 buffer 标题和任务内容会随 query 刷新。

## 8. 测试 toggle + save

在 `Tasks: inbox` 结果里，把光标放到：

```text
#task Inbox item
```

按：

```vim
<space>
<c-s>
```

检查源文件：

```vim
:edit /private/tmp/obsidian-tasks-nvim-phase2-vault/Daily/2026-05-14.md
```

预期：

```markdown
- [x] #task Inbox item 📅 2026-05-14
```

再手动改回 `[ ]`，方便继续测试。

## 9. 测试 refresh

打开：

```vim
:ObsidianTasks inbox
```

在另一个窗口或 buffer 中把某个任务改成完成，再回到 Tasks panel 按：

```vim
<c-r>
```

预期：

- 当前 query 会重新执行。
- 完成任务会从 `not done` 查询结果中消失。

## 10. 测试 query 错误 buffer

```vim
:ObsidianTasksQuery unknown instruction
```

预期：

- 打开一个错误 buffer。
- 显示 `Query errors:`。
- 显示 `Unsupported query instruction`。

## 11. 测试空结果 buffer

```vim
:lua require("obsidian-tasks").run_query("not done\npriority is highest\ndue before 2000-01-01")
```

预期：

- 打开 Tasks buffer。
- 顶部显示 `Showing 0 tasks`。
- 没有任务行，但不是只弹 notify。

## 12. 测试 date / happens

```vim
:ObsidianTasks by_happens
```

预期：

- 能按 happens 日期分组。
- `Started item` 的 happens 应该来自 start date `2026-05-13`。
- 普通 due task 的 happens 来自 due date。

## 13. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase2.sh
```

预期没有输出或只输出保存提示，退出码为 0。

## 14. 本阶段已知限制

- Phase 2 只发现 `setup({ queries = ... })` 中的 config queries。
- vault 中的 named `tasks` code block 自动发现放到 Phase 3。
- `:ObsidianTasksRunBlock` 和 inline preview 放到 Phase 3。
- Boolean / regex / function query 暂未支持。
- custom status registry、recurrence 完成生成下一次任务、done date 自动写回仍未实现。

## 15. 常见问题

### 没有 `:ObsidianTasks` 命令

先检查当前是否加载到了正确插件：

```vim
:lua print(vim.inspect(package.loaded["obsidian-tasks"] ~= nil))
:lua print(vim.inspect(require("obsidian-tasks").config))
```

再检查 runtimepath 是否包含当前工程目录：

```vim
:set runtimepath?
```

需要能看到：

```text
/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim
```

如果你是在已经打开的 Neovim 里临时执行了 `:set rtp+=...`，`plugin/` 目录下的自动加载脚本可能不会补跑。可以手动执行一次：

```vim
:lua require("obsidian-tasks").setup({ vault_path = "/private/tmp/obsidian-tasks-nvim-phase2-vault", global_filter = "#task", default_query = "due_soon", queries = { due_soon = "not done\nsort by due" } })
```

然后再检查：

```vim
:command ObsidianTasks
```
