# Phase 6.5 手动测试步骤

这份文档用于手动验证 calendar date picker、select date menu 和 form buffer 日期选择。

## 1. 准备任务

在 vault 中新建一个 Markdown 文件，例如 `Calendar Test.md`：

```markdown
- [ ] #task Existing due 📅 2026-05-20
- [ ] #task Empty scheduled
- [ ] #task Empty start
```

确认你的 Neovim 配置已加载本地插件：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  date_picker = {
    style = "select",
  },
})
```

## 2. 普通 task 行打开 calendar

把光标放到第一条任务上：

```markdown
- [ ] #task Existing due 📅 2026-05-20
```

执行：

```vim
:ObsidianTasksPickDate! due
```

预期：

- 打开 `obsidian-tasks://date-picker` floating buffer。
- 第一行显示当前月份和 `field: due`。
- 如果任务已有 due date，会显示 `Current: 2026-05-20`。

在 calendar 中按：

```vim
l
<CR>
```

预期源任务 due date 被更新为下一天。

## 3. 清空日期

把光标仍放在第一条任务上，执行：

```vim
:ObsidianTasksPickDate! due
```

在 calendar 中按：

```vim
c
```

预期第一条任务中的 `📅 YYYY-MM-DD` 被移除。

## 4. 写入其它 date field

把光标放到第二条任务：

```markdown
- [ ] #task Empty scheduled
```

执行：

```vim
:ObsidianTasksPickDate! scheduled
```

在 calendar 中移动到目标日期后按 `<CR>`。

预期任务行追加 scheduled date：

```markdown
⏳ YYYY-MM-DD
```

再把光标放到第三条任务，执行：

```vim
:ObsidianTasksPickDate! start
```

预期任务行追加 start date：

```markdown
🛫 YYYY-MM-DD
```

## 5. 验证 select date menu

把光标放到已有日期的任务上，执行不带 bang 的命令：

```vim
:ObsidianTasksPickDate due
```

预期打开 `vim.ui.select` 菜单，至少包含：

- `Clear`
- `Advance 1 day`
- `Postpone 1 day`
- `Today`
- `Tomorrow`
- `Custom...`
- `Calendar...`

选择 `Calendar...` 后，预期进入同一个 floating calendar。

## 6. Form buffer 中使用 calendar

如果希望 form buffer 的 `gd` 默认打开 calendar，把配置改为：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  date_picker = {
    style = "calendar",
  },
})
```

打开任意任务的 edit form：

```vim
:ObsidianTasksEdit
```

把光标移动到 `due:`、`scheduled:` 或 `start:` 字段，按：

```vim
gd
```

预期：

- 打开 calendar picker。
- `<CR>` 选择日期后，form 字段被写成 `YYYY-MM-DD`。
- `c` 清空后，form 字段变为空。

保存 form：

```vim
<C-S>
```

预期源任务行写入或移除对应 emoji date field。

## 7. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase6_5.sh
```

建议再跑：

```sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase5_5.sh
sh scripts/smoke_phase6_4.sh
```
