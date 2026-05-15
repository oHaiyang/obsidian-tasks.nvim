# Phase 4 手动测试步骤

这份文档用于手动验证 Phase 4 的 status registry、状态命令、done/cancelled date、recurrence、dependencies 查询和 postpone。

## 1. 准备临时测试 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase4-vault
rm -rf "$VAULT"
mkdir -p "$VAULT/Projects"

cat > "$VAULT/Projects/Phase4.md" <<'EOF'
# Phase 4

- [ ] #task Todo item 📅 2026-05-15
- [/] #task In progress item 📅 2026-05-16
- [-] #task Cancelled item ❌ 2026-05-10
- [ ] #task Daily review 🔁 every day 📅 2026-05-15
- [ ] #task Parent task 🆔 parent
- [ ] #task Child task ⛔ parent
- [x] #task Done parent 🆔 done-parent
- [ ] #task Free child ⛔ done-parent
- [ ] #task Scheduled only ⏳ 2026-05-18
- [ ] #task Start only 🛫 2026-05-19
EOF
```

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase4-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

local tasks = require("obsidian-tasks")

tasks.setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase4-vault",
  global_filter = "#task",
  default_query = "open",
  set_done_date = true,
  set_cancelled_date = true,
  recurrence_on_next_line = true,
  queries = {
    open = [[
not done
sort by due
]],
    blocked = [[
is blocked
]],
    blocking = [[
is blocking
]],
    progress = [[
status.type is IN_PROGRESS
]],
  },
})
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase4-init.lua /private/tmp/obsidian-tasks-nvim-phase4-vault/Projects/Phase4.md
```

确认命令存在：

```vim
:command ObsidianTasksToggle
:command ObsidianTasksChangeStatus
:command ObsidianTasksPostpone
:command ObsidianTasksStatusDone
:command ObsidianTasksStatusInProgress
:command ObsidianTasksStatusCancelled
```

## 4. 测试 Markdown buffer 中的 status command

把光标放在 `Todo item` 行，执行：

```vim
:ObsidianTasksChangeStatus In Progress
```

预期当前行变成：

```markdown
- [/] #task Todo item 📅 2026-05-15
```

说明：这里的 `📅 2026-05-15` 是测试数据里原本存在的 due date。切到 `IN_PROGRESS` 只改变 checkbox status，不会自动新增 `✅`、`❌` 或 `🛫` 日期。

再执行：

```vim
:ObsidianTasksStatusDone
```

预期：

- 当前行状态变成 `[x]`。
- 行尾增加 `✅ 今天日期`。

再执行：

```vim
:ObsidianTasksChangeStatus Todo
```

预期：

- 状态变回 `[ ]`。
- `✅ YYYY-MM-DD` 被移除。

## 5. 测试 cancelled date

把光标放到 `Todo item` 或其他未完成任务行，执行：

```vim
:ObsidianTasksStatusCancelled
```

预期：

- 状态变成 `[-]`。
- 行尾增加 `❌ 今天日期`。

再执行：

```vim
:ObsidianTasksChangeStatus Todo
```

预期 `❌ YYYY-MM-DD` 被移除。

## 6. 测试 recurring completion

把光标放到：

```markdown
- [ ] #task Daily review 🔁 every day 📅 2026-05-15
```

执行：

```vim
:ObsidianTasksStatusDone
```

预期：

- 原任务变成 `[x]` 并带 `✅ 今天日期`。
- 下一行新增一条 `[ ]` 任务。
- 新任务的 due date 往后一天，例如 `📅 2026-05-16`。
- 新任务不包含 `✅`、`❌`、`🆔`、`⛔`。

## 7. 测试 postpone

把光标放到 `Todo item` 行，执行：

```vim
:ObsidianTasksPostpone 2026-05-20
```

预期 due date 变成：

```markdown
📅 2026-05-20
```

把光标放到 `Scheduled only` 行，执行：

```vim
:ObsidianTasksPostpone +2
```

预期 `⏳ 2026-05-18` 变成 `⏳ 2026-05-20`。

把光标放到 `Start only` 行，执行：

```vim
:ObsidianTasksPostpone tomorrow
```

预期修改 `🛫` start date。

## 8. 测试 dependency 查询

执行：

```vim
:ObsidianTasks blocked
```

预期：

- 显示 `Child task`。
- 不显示 `Free child`，因为它依赖的 `Done parent` 已完成。

执行：

```vim
:ObsidianTasks blocking
```

预期：

- 显示 `Parent task`。
- 不显示 `Done parent`。

## 9. 测试 status.type 查询

执行：

```vim
:ObsidianTasks progress
```

预期只显示 `[/]` 的任务。

也可以临时查询：

```vim
:ObsidianTasksQuery status.type is CANCELLED
```

预期显示 `[-]` 的任务。

## 10. 测试 result buffer 编辑

执行：

```vim
:ObsidianTasks open
```

在结果 buffer：

- `<space>`：按 next status toggle 当前任务。
- `s`：打开 status picker。
- `p`：postpone 当前任务，并刷新结果。
- `<c-s>`：保存 status 修改回源文件。

验收：

- status 修改后不保存不会影响源文件。
- `<c-s>` 后源文件对应行被写回。
- 如果保存的是 recurring task 完成状态，源文件中会生成下一次任务。

## 11. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase4.sh
```

预期无错误退出。

## 12. 已知限制

- recurrence parser 还不是原插件完整版本。
- postpone 暂未支持完整自然语言日期。
- result buffer 的 postpone 会立即写回源文件；status 修改仍沿用显式保存模型。
- 还没有编辑 modal、日期 picker 和 dependency editor。
