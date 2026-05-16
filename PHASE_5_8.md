# Phase 5.8: Optional nvim-cmp Source

目标：把 Phase 5.7 的 completion core 接到 `nvim-cmp`，让 form buffer 和普通 Markdown task 行都可以出现在用户已有的 cmp 补全菜单中。

状态：已实现第一版，手动测试步骤见 `PHASE_5_8_TEST.md`，headless smoke 见 `scripts/smoke_phase5_8.sh`。

## 范围

新增：

- `lua/obsidian-tasks/completion/cmp.lua`
- `require("obsidian-tasks").setup_cmp(opts)`
- `setup({ completion = { cmp = true } })` 可选自动注册 source

Source 名称默认是：

```lua
obsidian-tasks
```

如果没有安装 `nvim-cmp`，注册会安静失败，不影响插件其它功能。

## 配置

手动注册：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
})

require("obsidian-tasks").setup_cmp()
```

或者在 setup 中注册：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  completion = {
    cmp = true,
  },
})
```

然后把 source 加进 `nvim-cmp`：

```lua
local cmp = require("cmp")

cmp.setup.filetype({ "markdown", "obstasks-form" }, {
  sources = cmp.config.sources({
    { name = "obsidian-tasks" },
    { name = "buffer" },
    { name = "path" },
  }),
})
```

也可以自定义 source name：

```lua
require("obsidian-tasks").setup_cmp({
  name = "tasks",
})
```

对应 cmp source 配置改成：

```lua
{ name = "tasks" }
```

## 行为

Source 会复用 `completion.lua`：

- `filetype=obstasks-form`：走 form context。
- `filetype=markdown` / `md`：只在 Markdown checklist task 行返回 items。
- 普通 Markdown 段落返回空 items。

Markdown task 行中：

- `📅 tom` 返回 ISO 日期 insert text。
- `🔁 every w` 返回 recurrence snippets。
- `⛔ alpha-id, b` 返回已有 task id。
- `h` 返回 priority emoji。

Form buffer 中：

- `priority: h` 返回 `high` / `highest` 等文本值。
- `due: tom` 返回自然日期表达式，仍由保存时正规化。
- `depends_on: b` 返回已有 task id。

## 已知限制

- Source 目前不主动配置 cmp keymaps。
- 普通 Markdown buffer 依旧不会自动启用原生 popup；是否弹出由 `nvim-cmp` 自己决定。
- cmp item 使用 `insertText` 和 source response `offset` 控制替换范围；复杂多字节边界后续继续用真实配置打磨。

## Phase 5.8 验收

- 没装 `nvim-cmp` 时 `setup({ completion = { cmp = true } })` 不报错。
- cmp source object 可以在 Markdown task 行返回 due/recurrence/dependency/priority items。
- cmp source object 可以在 form buffer 返回 form field items。
- 普通 Markdown 段落返回空 items。
- Phase 5.7/5.6/5.5 smoke 无回归。
