# Phase 5.1 手动测试步骤

这份文档用于手动验证 Phase 5.1 的括号 Boolean Query。

## 1. 准备临时测试 vault

```sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-1-vault
rm -rf "$VAULT"
mkdir -p "$VAULT"

cat > "$VAULT/Boolean.md" <<'EOF'
# Boolean

- [ ] #task Alpha work item 📅 2026-05-20
- [ ] #task Beta home item 📅 2026-05-21
- [ ] #task Later someday item 📅 2026-06-01
- [x] #task Done archive item ✅ 2026-05-10
EOF
```

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase5-1-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

require("obsidian-tasks").setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase5-1-vault",
  global_filter = "#task",
  queries = {
    nested = [[
(not done) AND ((description includes Alpha) OR (description includes Beta))
]],
    and_not = [[
(not done) AND NOT (description includes someday)
]],
    mixed = [[
not done
(description includes Alpha) OR (description includes Beta)
]],
  },
})
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-1-init.lua /private/tmp/obsidian-tasks-nvim-phase5-1-vault/Boolean.md
```

## 4. 测试嵌套 AND / OR

```vim
:ObsidianTasks nested
```

预期显示：

- `Alpha work item`
- `Beta home item`

不显示：

- `Later someday item`
- `Done archive item`

## 5. 测试 AND NOT

```vim
:ObsidianTasks and_not
```

预期显示 Alpha 和 Beta，不显示 `Later someday item`。

## 6. 测试和普通多行 query 混用

```vim
:ObsidianTasks mixed
```

预期显示 Alpha 和 Beta。

## 7. 测试临时 query

```vim
:ObsidianTasksQuery NOT (done)
```

预期显示所有未完成任务。

```vim
:ObsidianTasksQuery (done) OR (description includes someday)
```

预期显示 `Done archive item` 和 `Later someday item`。

## 8. 测试错误提示

```vim
:ObsidianTasksQuery (not done) AND
```

预期进入 query error buffer，提示 Boolean operator 需要左右 filter。

```vim
:ObsidianTasksQuery (not done
```

预期进入 query error buffer，提示括号不匹配。

## 9. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_1.sh
```

预期无错误退出。

## 10. 已知限制

- 暂不支持 `XOR`。
- 暂不支持原版的 bracket / quote delimiters。
- `preset name` 作为完整 query line 可用；单行 `{{preset.name}}` 在 Boolean 表达式内展开已在 Phase 5.2 支持。
