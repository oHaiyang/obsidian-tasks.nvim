# Phase 5.8 手动测试步骤

这份文档用于手动验证可选 `nvim-cmp` source。

## 1. 准备配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  completion = {
    cmp = true,
  },
})

local cmp = require("cmp")

cmp.setup.filetype({ "markdown", "obstasks-form" }, {
  sources = cmp.config.sources({
    { name = "obsidian-tasks" },
    { name = "buffer" },
    { name = "path" },
  }),
})
```

如果你不想在 `setup()` 里注册，也可以：

```lua
require("obsidian-tasks").setup_cmp()
```

## 2. 测试普通 Markdown task 行

在 Markdown 文件中准备：

```markdown
- [ ] #task Existing dependency 🆔 alpha-id
- [ ] #task Another dependency 🆔 beta-id
- [ ] #task Due field 📅 tom
- [ ] #task Recurring field 🔁 every w
- [ ] #task Depends field ⛔ alpha-id, b
- [ ] #task Priority field h
Plain paragraph 📅 tom
```

预期：

- `📅 tom` 能在 cmp 菜单里看到明天的 ISO 日期。
- `🔁 every w` 能看到 `every week`。
- `⛔ alpha-id, b` 能看到 `beta-id`。
- `Priority field h` 能看到 priority emoji。
- 普通段落 `Plain paragraph 📅 tom` 不应该返回 obsidian-tasks 建议。

## 3. 测试 form buffer

执行：

```vim
:ObsidianTasksEdit
```

在 form buffer 中：

- `priority: h` 应返回 `high` / `highest`。
- `due: tom` 应返回 `tomorrow`。
- `depends_on: b` 应返回已有 task id。

## 4. 测试 fallback

即使没有启用 cmp source，以下入口仍应保留：

```vim
:ObsidianTasksComplete
```

以及：

```vim
<Plug>(ObsidianTasksComplete)
```

## 5. 测试 smoke

```sh
sh /Users/haiyang/Coding/nvim-tasks/obsidian-tasks.nvim/scripts/smoke_phase5_8.sh
```

预期命令退出码为 0。
