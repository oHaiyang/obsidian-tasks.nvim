# Phase 5.2 手动测试步骤

这份文档用于手动验证 query context、placeholders 和 preset placeholder。

## 1. 准备临时测试 vault

````sh
VAULT=/private/tmp/obsidian-tasks-nvim-phase5-2-vault
rm -rf "$VAULT"
mkdir -p "$VAULT/Projects" "$VAULT/Other"

cat > "$VAULT/Projects/Dashboard.md" <<'EOF'
# Dashboard

- [ ] #task Dashboard local item
EOF

cat > "$VAULT/Projects/ProjectBoard.md" <<'EOF'
# Project Board

```tasks
# name: Project Folder
# id: project-folder
folder includes {{query.file.folder}}
```

- [ ] #task Project board local item
EOF

cat > "$VAULT/Projects/Alpha.md" <<'EOF'
# Alpha

- [ ] #task Alpha project item
EOF

cat > "$VAULT/Projects/Beta.md" <<'EOF'
# Beta

- [ ] #task Beta project item
EOF

cat > "$VAULT/Other/Gamma.md" <<'EOF'
# Gamma

- [ ] #task Gamma external item
EOF
````

## 2. 创建临时 Neovim 启动配置

```sh
cat > /private/tmp/obsidian-tasks-phase5-2-init.lua <<'EOF'
vim.opt.runtimepath:prepend("/Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim")

local vault = "/private/tmp/obsidian-tasks-nvim-phase5-2-vault"

require("obsidian-tasks").setup({
  vault_path = vault,
  global_filter = "#task",
  enable_lua_filters = true,
  presets = {
    dashboard_only = "path includes {{query.file.path}}",
    project_folder = "folder includes {{query.file.folder}}",
    alpha_filter = "description includes Alpha",
  },
  queries = {
    dashboard_config = {
      source_path = vault .. "/Projects/Dashboard.md",
      source_line = 1,
      query = "preset this_file",
    },
    boolean_preset = {
      source_path = vault .. "/Projects/Dashboard.md",
      source_line = 1,
      query = "({{preset.alpha_filter}}) OR (description includes Dashboard)",
    },
    folder_function = {
      source_path = vault .. "/Projects/ProjectBoard.md",
      source_line = 1,
      query = "filter by function task.file.folder == query.file.folder",
    },
  },
})
EOF
```

## 3. 启动 Neovim

```sh
nvim -u /private/tmp/obsidian-tasks-phase5-2-init.lua /private/tmp/obsidian-tasks-nvim-phase5-2-vault/Projects/ProjectBoard.md
```

## 4. 测试 block query placeholder

先刷新 block query：

```vim
:ObsidianTasksRefreshQueries
```

运行 code block 里的 query：

```vim
:ObsidianTasks project-folder
```

预期显示 Projects 文件夹下的 4 个任务：

- `Dashboard local item`
- `Project board local item`
- `Alpha project item`
- `Beta project item`

不显示：

- `Gamma external item`

## 5. 测试 config query source_path

```vim
:ObsidianTasks dashboard_config
```

预期只显示 `Dashboard local item`。

## 6. 测试 `{{preset.name}}` 在 Boolean 中展开

```vim
:ObsidianTasks boolean_preset
```

预期显示：

- `Alpha project item`
- `Dashboard local item`

## 7. 测试 function filter 读取 `query.file`

```vim
:ObsidianTasks folder_function
```

预期显示 Projects 文件夹下的 4 个任务，不显示 `Gamma external item`。

## 8. 测试 preview 使用同一套 context

把光标放在 `ProjectBoard.md` 的 tasks code block 附近，执行：

```vim
:ObsidianTasksPreviewToggle
```

预期 code block 下方显示 preview，数量类似 `Showing 4 of 4`，且不包含 `Gamma external item`。

## 9. 测试缺少 query file context 的错误

```vim
:ObsidianTasksQuery path includes {{query.file.path}}
```

预期进入 query error buffer，提示没有 query file path。

## 10. Headless smoke

可以直接跑：

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_2.sh
```

预期无错误退出。

## 11. 已知限制

- `:ObsidianTasksQuery` 这种纯手写命令默认没有 query file context。
- `this_root` 复用当前 task file model 的 `root` 字段；在绝对路径下通常是 `/`，实际使用中 `this_file` 和 `this_folder` 更有价值。
- Query File Defaults 已在 Phase 5.3 实现；本测试仍只覆盖 Phase 5.2 的 placeholder 能力。
