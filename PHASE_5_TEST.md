# Phase 5 手动测试步骤

这份文档用于手动验证 Phase 5 的 advanced query MVP 和任务编辑表单。

## 1. 准备临时测试 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-vault
rm -rf "$VAULT"
mkdir -p "$VAULT/Projects" "$VAULT/Home"

cat > "$VAULT/Projects/Phase5.md" <<'EOF'
# Phase 5

- [ ] #task Alpha work item 📅 2026-05-20
- [ ] #task Beta home item 📅 2026-05-21
- [x] #task Done archive item ✅ 2026-05-10
- [ ] #task Weekly review 🔁 every week 📅 2026-05-22 🆔 review
EOF
```

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase5-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

local tasks = require("obsidian-tasks")

tasks.setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase5-vault",
  global_filter = "#task",
  enable_lua_filters = true,
  inbox_file = "/private/tmp/obsidian-tasks-nvim-phase5-vault/Projects/Phase5.md",
  presets = {
    open_alpha = [[
not done
description includes Alpha
]],
  },
  queries = {
    regex_review = [[
description regex matches /review/i
]],
    work_or_done = [[
not done
description includes work
OR
done
description includes archive
]],
    preset_alpha = [[
preset open_alpha
]],
    lua_filter = [[
filter by function task.description:find("home", 1, true) ~= nil
]],
  },
})
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-init.lua /private/tmp/obsidian-tasks-nvim-phase5-vault/Projects/Phase5.md
```

确认命令存在：

```vim
:command ObsidianTasksEdit
:command ObsidianTasksCreate
```

## 4. 测试 regex query

```vim
:ObsidianTasks regex_review
```

预期只显示 `Weekly review`。

也可以临时查询：

```vim
:ObsidianTasksQuery description regex matches /Alpha|Beta/
```

预期显示 Alpha 和 Beta 两条任务。

## 5. 测试 OR query

```vim
:ObsidianTasks work_or_done
```

预期显示：

- `Alpha work item`
- `Done archive item`

不显示 `Beta home item`。

括号 Boolean 的完整测试见 `PHASE_5_1_TEST.md`。

## 6. 测试 preset

```vim
:ObsidianTasks preset_alpha
```

预期只显示 `Alpha work item`。

如果写错 preset：

```vim
:ObsidianTasksQuery preset missing_name
```

预期进入 query error buffer，提示 unknown preset。

## 7. 测试 function filter

```vim
:ObsidianTasks lua_filter
```

预期只显示 `Beta home item`。

说明：这里的 `filter by function` 使用 Lua 表达式，不是 JavaScript。需要 `enable_lua_filters = true`。

## 8. 测试编辑当前 Markdown task

回到 `Phase5.md`，把光标放在 `Alpha work item` 行，执行：

```vim
:ObsidianTasksEdit
```

在表单里改：

```text
description: Alpha edited #task
status: In Progress
priority: high
due: 2026-05-25
```

保存：

```vim
<C-S>
```

预期源文件行变成类似：

```markdown
- [/] Alpha edited #task ⏫ 📅 2026-05-25
```

## 9. 测试从结果 buffer 编辑

```vim
:ObsidianTasks regex_review
```

在 `Weekly review` 那行按：

```vim
e
```

修改表单并保存后，预期写回源文件对应行。

## 10. 测试创建任务

在 `Phase5.md` 任意行执行：

```vim
:ObsidianTasksCreate
```

填入：

```text
description: Created from form #task
status: Todo
due: 2026-05-30
```

保存后，预期当前行下方插入：

```markdown
- [ ] Created from form #task 📅 2026-05-30
```

## 11. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5.sh
```

预期无错误退出。

## 12. 已知限制

- Boolean 括号表达式已在 Phase 5.1 支持。
- Regex 当前基于 Neovim `vim.regex()`，不是完整 JavaScript Regex。
- Function filter 是 Lua 表达式，并需要显式开启。
- 表单是普通 buffer MVP，不是完整 modal，也没有 auto-suggest。
- Placeholders 已在 Phase 5.2 支持；Query File Defaults 已在 Phase 5.3 支持；Dataview 格式、frontmatter/links 暂未实现。
