# Phase 5.3 手动测试步骤

这份文档用于手动验证 global query、`ignore global query` 和 Query File Defaults。

## 1. 准备临时测试 vault

````sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-3-vault
rm -rf "$VAULT"
mkdir -p "$VAULT/Projects" "$VAULT/Other"

cat > "$VAULT/Projects/Dashboard.md" <<'EOF'
---
TQ_extra_instructions: |-
  folder includes {{query.file.folder}}
TQ_short_mode: true
TQ_show_task_count: true
---
# Dashboard

```tasks
# name: Project Open
# id: project-open
not done
sort by filename
```

```tasks
# name: Project Open Ignoring Global
# id: project-open-ignore-global
ignore global query
not done
sort by filename
```

- [ ] #task Dashboard visible
- [ ] #task GlobalHidden dashboard
- [x] #task Dashboard done ✅ 2026-05-15
EOF

cat > "$VAULT/Projects/Alpha.md" <<'EOF'
# Alpha

- [ ] #task Alpha visible
EOF

cat > "$VAULT/Other/Gamma.md" <<'EOF'
# Gamma

- [ ] #task Gamma visible
EOF
````

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase5-3-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

require("obsidian-tasks").setup({
  vault_path = "/private/tmp/obsidian-tasks-nvim-phase5-3-vault",
  global_filter = "#task",
  global_query = "description does not include GlobalHidden",
})
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-3-init.lua /private/tmp/obsidian-tasks-nvim-phase5-3-vault/Projects/Dashboard.md
```

## 4. 测试 Query File Defaults + Global Query

刷新 block query：

```vim
:ObsidianTasksRefreshQueries
```

运行第一个 query：

```vim
:ObsidianTasks project-open
```

预期显示：

- `Dashboard visible`
- `Alpha visible`

不显示：

- `GlobalHidden dashboard`，因为被 `global_query` 排除。
- `Gamma visible`，因为被 `TQ_extra_instructions` 的 `folder includes {{query.file.folder}}` 排除。
- `Dashboard done`，因为 query 自己有 `not done`。

## 5. 测试 ignore global query

```vim
:ObsidianTasks project-open-ignore-global
```

预期显示：

- `Dashboard visible`
- `GlobalHidden dashboard`
- `Alpha visible`

仍不显示：

- `Gamma visible`
- `Dashboard done`

## 6. 测试 preview 使用 composition

```vim
:ObsidianTasksPreviewToggle
```

预期两个 tasks block 下方都有 preview：

- 第一个类似 `Showing 2 of 2`。
- 第二个类似 `Showing 3 of 3`。

## 7. 测试 layout directives 不报错

当前 frontmatter 中有：

```yaml
TQ_short_mode: true
TQ_show_task_count: true
```

运行 query 时不应进入 query error buffer。真正隐藏/显示字段的 UI 行为放到 Phase 5.4。

## 8. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_3.sh
```

预期无错误退出。

## 9. 已知限制

- frontmatter parser 是轻量 YAML 子集，主要覆盖 Obsidian properties 常见写法。
- `TQ_*` 属性写入命令暂未实现。
- layout directives 已解析，但还没有真正控制结果视图。
