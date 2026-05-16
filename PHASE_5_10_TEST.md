# Phase 5.10 手动测试步骤

这份文档用于手动验证 `Add Query File Defaults properties` 命令。

## 1. 准备测试 vault

创建一个临时 vault，例如：

```sh
mkdir -p /tmp/obsidian-tasks-phase5-10
```

创建没有 frontmatter 的 query note：

````markdown
# No Defaults

```tasks
not done
```
````

创建已有 frontmatter 的 query note：

```markdown
---
title: Existing Defaults
TQ_extra_instructions: |-
  folder includes Projects
TQ_show_tree: true
---

# Existing Defaults
```

## 2. 临时加载插件

在 `obsidian-tasks.nvim` 目录启动：

```sh
nvim -u NONE \
  --cmd 'set rtp+=.' \
  --cmd 'runtime plugin/obsidian-tasks.lua' \
  /tmp/obsidian-tasks-phase5-10/NoDefaults.md
```

进入 Neovim 后执行：

```vim
:lua require("obsidian-tasks").setup({ vault_path = "/tmp/obsidian-tasks-phase5-10" })
```

确认命令存在：

```vim
:echo exists(":ObsidianTasksAddQueryFileDefaults")
```

应返回 `2`。

## 3. 无 frontmatter 文件

在 `NoDefaults.md` 执行：

```vim
:ObsidianTasksAddQueryFileDefaults
```

预期：

- 文件顶部新增 YAML frontmatter。
- `TQ_*` 属性按字母序写入。
- 原正文仍在 frontmatter 后面。
- 消息提示 `Properties updated successfully.`

再次执行同一命令：

```vim
:ObsidianTasksAddQueryFileDefaults
```

预期：

- 不新增重复属性。
- 消息提示 `All supported properties are already present.`

## 4. 已有 frontmatter 文件

打开已有 frontmatter 的 note：

```vim
:edit /tmp/obsidian-tasks-phase5-10/ExistingDefaults.md
:ObsidianTasksAddQueryFileDefaults
```

预期：

- `title: Existing Defaults` 保留。
- `TQ_show_tree: true` 保留。
- `TQ_extra_instructions: |-` 和缩进内容保留。
- 缺失的其它 `TQ_*` 属性被补到 closing `---` 前。
- 重复执行不会产生重复属性。

## 5. Query File Defaults 读取验证

保存文件后执行：

```vim
:lua print(require("obsidian-tasks.query_file_defaults").source({ query_file_path = vim.api.nvim_buf_get_name(0) }))
```

预期输出包含：

```text
folder includes Projects
show tree
```

空值属性不应生成额外 query instruction，例如空的 `TQ_explain:` 不应输出 `explain`。

## 6. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase5_10.sh
```

回归检查：

```sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase5_8.sh
sh scripts/smoke_phase5_3.sh
```
