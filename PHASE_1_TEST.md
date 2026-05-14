# Phase 1 手动测试步骤

这份文档用于把当前 `obsidian-tasks.nvim` 的 Phase 1 实现加载到 Neovim 里手动测试。

测试目标：

- 不改动你平时的 Neovim 配置也能启动插件。
- 验证纯 Lua task parser / scanner / global filter。
- 验证普通 Markdown buffer 中直接 toggle。
- 验证查询结果 buffer 中 toggle、保存、跳转、刷新。

以下路径按当前本机仓库位置写死：

```text
/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim
```

如果之后目录变了，把命令里的这个路径替换掉即可。

## 1. 准备临时测试 vault

建议先用 `/private/tmp` 下的临时 vault 测，不污染真实 Obsidian vault。

在 shell 里执行：

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase1-vault
rm -rf "$VAULT"
mkdir -p "$VAULT/Projects" "$VAULT/Daily"

cat > "$VAULT/Projects/Project A.md" <<'EOF'
# Project A

- [ ] #task Write parser 🔼 📅 2026-05-13
- [x] #task Existing done ✅ 2026-05-12
- [ ] No global filter tag

## Nested

1) [ ] #task Numbered task ⏫ 🛫 2026-05-14
* [ ] #task Star task 🔺
+ [ ] #task Plus task 🔽

~~~
- [ ] #task Should not be scanned inside fenced block
~~~
EOF

cat > "$VAULT/Daily/2026-05-13.md" <<'EOF'
# Daily Note

> - [ ] #task Callout task 📅 2026-05-15
- [ ] #task Task with [ ] in description 📅 2026-05-16
- [ ] #task Task with dependency 🆔 abc123
- [ ] #task Depends on first ⛔ abc123
- [ ] #task Recurring placeholder 🔁 every week 📅 2026-05-20
EOF
```

预期：

- 真实可扫描任务一共 11 个。
- 带 `#task` 的任务一共 10 个。
- fenced block 里的任务不应该出现。

## 2. 创建临时 Neovim 启动配置

这个配置只用于本次测试，不会影响你的日常 `init.lua`。

```sh
cat > /private/tmp/obsidian-tasks-phase1-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

local tasks = require("obsidian-tasks")

tasks.setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase1-vault",
  global_filter = "#task",
  display = {
    hierarchical_headings = false,
  },
})

vim.keymap.set("n", "<leader>tt", tasks.toggle_task_at_cursor, { desc = "Obsidian Tasks: toggle task" })
vim.keymap.set("n", "<leader>tf", function()
  tasks.find_tasks({
    group_by = {},
    float = false,
  })
end, { desc = "Obsidian Tasks: find tasks" })

vim.keymap.set("n", "<leader>tF", function()
  tasks.find_tasks({
    group_by = { "file" },
    float = false,
  })
end, { desc = "Obsidian Tasks: find tasks grouped by file" })

vim.keymap.set("n", "<leader>tp", function()
  tasks.find_tasks({
    group_by = { "priority" },
    float = false,
  })
end, { desc = "Obsidian Tasks: find tasks grouped by priority" })

vim.keymap.set("n", "<leader>ts", function()
  tasks.find_tasks({
    group_by = { "status" },
    float = false,
  })
end, { desc = "Obsidian Tasks: find tasks grouped by status" })

vim.keymap.set("n", "<leader>tq", function()
  tasks.find_tasks({
    group_by = { "file", "priority" },
    hierarchical_headings = true,
    float = false,
  })
end, { desc = "Obsidian Tasks: find tasks grouped hierarchically" })
EOF
```

## 3. 启动 Neovim

用临时配置打开测试 vault 中的一个文件：

```sh
nvim -u /private/tmp/obsidian-tasks-phase1-init.lua /private/tmp/obsidian-tasks-nvim-phase1-vault/Projects/Project\ A.md
```

进入 Neovim 后，先确认插件能加载：

```vim
:lua print(vim.inspect(require("obsidian-tasks").config))
```

预期：

- 能看到 `vault_path` 指向 `/private/tmp/obsidian-tasks-nvim-phase1-vault`。
- 能看到 `global_filter = "#task"`。

## 4. 测试普通 Markdown buffer 中 toggle

在 `Project A.md` 里，把光标放到这一行：

```markdown
- [ ] #task Write parser 🔼 📅 2026-05-13
```

执行：

```vim
<leader>tt
```

预期：

```markdown
- [x] #task Write parser 🔼 📅 2026-05-13
```

再执行一次：

```vim
<leader>tt
```

预期恢复为：

```markdown
- [ ] #task Write parser 🔼 📅 2026-05-13
```

再测试描述里有 `[ ]` 的情况：

```vim
:edit /private/tmp/obsidian-tasks-nvim-phase1-vault/Daily/2026-05-13.md
```

把光标放到：

```markdown
- [ ] #task Task with [ ] in description 📅 2026-05-16
```

执行：

```vim
<leader>tt
```

预期只改开头 checkbox：

```markdown
- [x] #task Task with [ ] in description 📅 2026-05-16
```

描述里的 `[ ]` 不应该被改掉。

## 5. 测试查询结果 buffer

执行：

```vim
<leader>tf
```

预期：

- 当前窗口切换到一个任务结果 buffer。
- 顶部有 help 行：

```text
-- Tasks List (q:close, <c-s>:save changes, <c-r>:refresh), J/K move between task --
```

- 结果里应该只出现带 `#task` 的任务。
- 不应该出现：

```text
No global filter tag
Should not be scanned inside fenced block
```

## 6. 测试结果 buffer 中 toggle + 保存写回

在查询结果 buffer 中：

1. 用 `J` / `K` 在任务之间移动。
2. 把光标放到某个任务行。
3. 按 `<space>` 切换状态。
4. 按 `<c-s>` 保存回源文件。

然后跳回源文件检查。

比如对这条任务操作：

```text
#task Task with [ ] in description 📅 2026-05-16
```

预期：

- 结果 buffer 中状态变为 `[x]`。
- 保存后源文件只改变开头 checkbox。
- 描述里的 `[ ]` 仍然保留。

如果想用命令保存，也可以执行：

```vim
:lua require("obsidian-tasks").save_current_tasks()
```

## 7. 测试跳转源文件

在查询结果 buffer 中，把光标放到任意任务行，执行：

```vim
gd
```

或：

```vim
gf
```

预期：

- 当前结果 buffer 关闭。
- Neovim 打开任务所在源文件。
- 光标跳到对应任务行。

## 8. 测试刷新

执行：

```vim
<leader>tf
```

进入结果 buffer 后，修改某个源文件里的任务，再回到结果 buffer 执行：

```vim
<c-r>
```

预期：

- 结果 buffer 会重新扫描 vault。
- 仍然使用同一个 `vault_path` 和 `global_filter`。

## 9. 测试分组

### 按文件分组

```vim
<leader>tF
```

预期出现类似：

```markdown
## Project A
## 2026-05-13
```

### 按优先级分组

```vim
<leader>tp
```

预期看到 `Highest`、`High`、`Medium`、`Low`、`Normal` 等分组。

### 按状态分组

```vim
<leader>ts
```

预期看到：

```markdown
## Pending
## Completed
```

### 多级层级分组

```vim
<leader>tq
```

预期分组标题使用层级 heading，而不是单行 `A > B` 风格。

## 10. 测试浮窗结果

可以直接执行：

```vim
:lua require("obsidian-tasks").find_tasks({ float = true })
```

预期：

- 结果出现在 floating window。
- `q` 可关闭。
- `<space>` 可 toggle。
- `<c-s>` 可保存。

## 11. 测试不使用 global filter

临时执行：

```vim
:lua require("obsidian-tasks").find_tasks({ global_filter = "" })
```

预期：

- `No global filter tag` 也会出现在结果里。
- fenced block 里的任务仍然不出现。

## 12. 测试 parser 目前支持的字段

可以用命令直接看解析结果：

```vim
:lua local t=require("obsidian-tasks.task"); print(vim.inspect(t.parse_line({ line="- [ ] #task Demo 🔺 🆔 abc ⛔ one,two 🏁 delete 🔁 every week ➕ 2026-05-01 🛫 2026-05-02 ⏳ 2026-05-03 📅 2026-05-04 ❌ 2026-05-05 ✅ 2026-05-06 ^blk" })))
```

重点确认：

- `priority = "highest"`
- `id = "abc"`
- `depends_on = { "one", "two" }`
- `on_completion = "delete"`
- `recurrence_rule = "every week"`
- `created_date/start_date/scheduled_date/due_date/cancelled_date/done_date`
- `block_link = "^blk"`

## 13. 常见问题

### `module 'obsidian-tasks' not found`

检查临时 init 里的 runtimepath 是否正确：

```lua
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")
```

也可以在 Neovim 里看：

```vim
:set runtimepath?
```

### `No tasks found in the vault.`

检查：

- `vault_path` 是否正确。
- 测试任务是否在 `.md` 文件里。
- 当前是否设置了 `global_filter = "#task"`。
- 任务行是否真的包含 `#task`。
- 任务是否写在 fenced code block 里。

### 保存后源文件没变化

在结果 buffer 中改了状态后，需要执行：

```vim
<c-s>
```

或：

```vim
:write
```

当前结果 buffer 是 `acwrite`，写入会触发保存回源文件。

### 跳转失败

结果 buffer 每条任务末尾会带：

```text
[[/path/to/file.md#L12]]
```

如果手动编辑破坏了这个尾部 metadata，`gd/gf` 就找不到源位置。

## 14. 本阶段已知限制

- status 目前只是简单 `[ ]` 和非空状态之间切换，没有 custom status registry。
- 完成任务不会自动加 `✅ done date`。
- recurring task 不会生成下一次任务。
- Dataview task format 暂未支持。
- query language 暂未实现，当前仍通过 Lua opts 传 filter/group。
- scanner 当前是同步递归扫描 `.md` 文件，真实大 vault 后续需要缓存和增量更新。
