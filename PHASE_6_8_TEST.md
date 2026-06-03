# Phase 6.8 手动测试步骤

这份文档用于手动验证 frontmatter properties、links 和 Lua function filter surface。

## 1. 准备文件

新建 `Project.md`：

```markdown
---
area: work
rating: 3
draft: false
tags: [project, focus]
aliases:
  - Work Note
cssclasses:
  - kanban
TQ_show_tree: true
TQ_extra_instructions: |
  not done
---

# Project

- [ ] #task Linked [[Project Alpha#Plan|Alpha]] and [Spec](docs/spec.md)
- [ ] #task Plain
```

再新建一个无 frontmatter 文件 `Plain.md`：

```markdown
# Plain

- [ ] #task No frontmatter
```

配置：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  enable_lua_filters = true,
})
```

## 2. 验证 task.frontmatter

运行：

```vim
:ObsidianTasksQuery filter by function task.frontmatter.area == "work"
```

预期：

- 显示 `Project.md` 中的两条任务。
- 不显示 `Plain.md` 中的任务。

## 3. 验证 task.file.tags

运行：

```vim
:ObsidianTasksQuery filter by function vim.tbl_contains(task.file.tags or {}, "project")
```

预期显示 `Project.md` 中的两条任务。

## 4. 验证 task.links

运行：

```vim
:ObsidianTasksQuery filter by function #(task.links or {}) > 0
```

预期只显示：

```markdown
- [ ] #task Linked [[Project Alpha#Plan|Alpha]] and [Spec](docs/spec.md)
```

## 5. 验证 query.file.tags

在 `Project.md` 中写一个 tasks block：

```tasks
filter by function vim.tbl_contains(query.file.tags or {}, "project")
```

在 block 上运行：

```vim
:ObsidianTasksQueryAtCursor
```

预期 query file context 能读取当前 note frontmatter tags。

## 6. 验证 Query File Defaults

在 `Project.md` 中运行任意当前文件 query 或刷新 tasks block。

预期 frontmatter 中：

```yaml
TQ_show_tree: true
TQ_extra_instructions: |
  not done
```

仍会被 Query File Defaults 读取，不因 Phase 6.8 的 parser 迁移而失效。

## 7. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase6_8.sh
```

建议再跑：

```sh
sh scripts/smoke_phase5_3.sh
sh scripts/smoke_phase5_10.sh
sh scripts/smoke_phase5.sh
```
