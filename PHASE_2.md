# Phase 2: Query Language + Tasks Panel MVP

目标：在 Phase 1 的 Task parser / scanner / write-back 基础上，补上可日常使用的查询语言和全局 Tasks 面板。

Phase 2 的重点不是完全复刻 Obsidian 的 inline rendering，而是先让用户在 Neovim 任意位置快速打开任务面板、切换常用查询、同时保留多个查询结果，并继续支持跳转、toggle、保存和刷新。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_2_TEST.md`，headless smoke 见 `scripts/smoke_phase2.sh`。

已覆盖：

- `date.lua`：`YYYY-MM-DD` 校验、比较、`today/tomorrow/yesterday`、`happens`。
- `query.lua`：基础 filters、date filters、sort、group、limit、错误收集。
- `sort.lua`：多级排序和 reverse。
- finder 集成 `find_tasks({ query = ... })`。
- `setup({ queries = ..., default_query = ... })`。
- `:ObsidianTasks`、`:ObsidianTasks! name`、`:ObsidianTasksQuery ...`。
- active/pinned result buffer、动态标题、task count、空结果 buffer、query error buffer。
- 结果 buffer 中 `o` query picker、`]q` / `[q` 切换、`gq` query source 提示。

仍留在 Phase 2 后续小修：

- 更完整的 query parser 单元测试覆盖。
- result buffer 样式和帮助行继续打磨。
- query picker 在 headless 之外的真实交互微调。

## 核心交互模型

Obsidian Tasks 的主入口是 Markdown 中的 `tasks` code block；Neovim 里直接照搬会有点笨重，因为用户必须先定位到某个文件和 block 才能打开任务列表。

本插件采用两层模型：

- `tasks` code block 和 config query 是“查询定义”。
- Tasks panel 是“查询入口和操作面”。

Phase 2 先支持 config query 作为主要查询来源：

```lua
require("obsidian-tasks").setup({
  vault_path = "...",
  global_filter = "#task",
  default_query = "inbox",
  queries = {
    inbox = [[
      not done
      sort by due
    ]],
    due_soon = [[
      not done
      due on or before 2026-05-20
      sort by due
      group by filename
    ]],
  },
})
```

日常入口：

```vim
:ObsidianTasks
:ObsidianTasks inbox
:ObsidianTasks! due_soon
```

建议 keymap：

```lua
vim.keymap.set("n", "<leader>to", require("obsidian-tasks").open, { desc = "Open Obsidian Tasks panel" })
```

交互预期：

- `:ObsidianTasks` 在任意位置打开 Tasks panel。
- 不带参数时打开上次 query；如果没有上次 query，则打开 `default_query`。
- 带 query name 时直接打开该 query。
- 普通命令复用当前 active Tasks panel。
- 带 bang 的 `:ObsidianTasks! name` 打开一个 pinned result buffer，用于同时查看多个查询。
- 面板内按 `o` 打开 query picker。
- 面板内按 `]q` / `[q` 切换下一个/上一个 query。
- 面板内按 `gq` 跳到 query 定义；Phase 2 中 config query 可以显示来源提示，Phase 3 再支持跳到 named block。
- 面板内继续支持 `<space>` toggle、`<c-s>` save、`<c-r>` refresh、`gd/gf` 跳任务源文件、`q` 关闭。

结果 buffer 示例：

```text
Tasks: due_soon                          Showing 12 of 43
Source: config queries

o queries  [q previous query  ]q next query  gq query source
<space> toggle  <c-s> save  <c-r> refresh  gd task source  q close

1. [ ] [HIGH] #task Finish query parser [[/vault/Project.md#L18]]
2. [ ] #task Write Phase 2 tests [[/vault/Daily/2026-05-14.md#L7]]
```

## 为什么 Phase 2 这样拆

- Phase 1 已经能稳定扫描任务并保留关键字段，查询语言可以直接复用这些字段。
- 全局 Tasks 面板比“先找到 code block 再运行”更符合 Neovim 的日常工作流。
- config query 先落地，可以避免一开始就实现 named block registry、vault-wide query discovery 和 inline preview。
- 多查询并排查看通过 pinned result buffer 解决，不需要发明一套复杂窗口系统。
- recurrence、custom status、done date 自动写回会改变源文件语义，适合等查询和面板稳定后再做。

## 设计原则

- 查询核心继续使用纯 Lua，新增核心模块尽量不直接依赖 `vim.api`。
- Query parser 先采用 line-based parser，不引入复杂语法生成器。
- 每一条 query 指令要么被明确支持，要么返回可读错误，不静默忽略。
- 内部先编译成统一 query plan，再由 finder 执行，避免把字符串解析逻辑散落在 UI 层。
- Tasks panel 是主入口；`run_query_at_cursor()` 和 `tasks` block execution 后续作为辅助入口。
- 先覆盖 Obsidian Tasks 最常用语法，复杂 Boolean、presets、placeholders 留到后续。

建议新增模块：

```text
lua/obsidian-tasks/query.lua
lua/obsidian-tasks/date.lua
lua/obsidian-tasks/sort.lua
lua/obsidian-tasks/panel.lua
```

## Phase 2 范围

### P2.1 Query parser MVP

实现 `lua/obsidian-tasks/query.lua`。

输入是一段 query 文本，例如：

```tasks
not done
due on or before 2026-05-20
priority is above low
tag includes #task
sort by due
sort by priority reverse
group by filename
limit 20
```

输出 query plan：

```lua
{
  filters = { ... },
  sorts = { ... },
  group_by = { "filename" },
  limit = 20,
  errors = {},
  warnings = {},
}
```

本阶段支持：

- 空行忽略。
- `# ...` 注释行忽略。
- `done`
- `not done`
- `status is <symbol>`
- `status is not <symbol>`
- `description includes <text>`
- `description does not include <text>`
- `tag includes <tag>`
- `tag does not include <tag>`
- `path includes <text>`
- `filename includes <text>`
- `heading includes <text>`
- `priority is highest|high|medium|normal|low|lowest|none`
- `priority is above <priority>`
- `priority is below <priority>`
- `has due date` / `no due date`
- `has scheduled date` / `no scheduled date`
- `has start date` / `no start date`
- `has done date` / `no done date`
- `has created date` / `no created date`
- `has cancelled date` / `no cancelled date`
- `due on YYYY-MM-DD`
- `due before YYYY-MM-DD`
- `due after YYYY-MM-DD`
- `due on or before YYYY-MM-DD`
- `due on or after YYYY-MM-DD`
- 同样的日期比较支持 `scheduled`、`start`、`done`、`created`、`cancelled`、`happens`
- `is recurring`
- `is not recurring`
- `has id`
- `no id`
- `has depends on`
- `no depends on`
- `sort by status`
- `sort by priority`
- `sort by due`
- `sort by scheduled`
- `sort by start`
- `sort by done`
- `sort by created`
- `sort by cancelled`
- `sort by happens`
- `sort by path`
- `sort by filename`
- `sort by heading`
- `sort by description`
- 每个 `sort by ...` 支持可选 `reverse`
- `group by status`
- `group by priority`
- `group by file`
- `group by filename`
- `group by heading`
- `group by due`
- `group by scheduled`
- `group by start`
- `group by done`
- `group by happens`
- `limit <n>`

明确暂缓：

- Boolean query：`AND` / `OR` / `XOR` / `NOT` 组合。
- Regex filters。
- Relative date ranges：`this week`、`next month` 等。
- `explain`。
- presets / placeholders / query file defaults。
- `filter by function` / `sort by function` / `group by function`。

验收：

- 不支持的 query 行显示清晰错误，结果 buffer 不应误展示旧结果。
- 同一段 query 支持多条 filter、sort、group 指令组合。
- query parser 有 headless smoke test 覆盖主要语句。

### P2.2 Date helper

实现 `lua/obsidian-tasks/date.lua`。

本阶段 date helper 只做稳定的基础能力：

- 校验 `YYYY-MM-DD` 是否是真实日期。
- 比较日期大小。
- 格式化 date field 缺失值，供排序和分组使用。
- 计算 `happens_date`：从 `start_date`、`scheduled_date`、`due_date` 中取最早的有效日期。
- 支持 `today`、`tomorrow`、`yesterday` 这三个高频相对日期。

为了测试稳定，date helper 需要允许注入 `today`：

```lua
date.parse_date_expr("today", { today = "2026-05-14" })
```

验收：

- 无效日期不会让查询崩溃。
- `happens` 查询、排序、分组结果和 start/scheduled/due 三者最早日期一致。
- 没有对应日期的任务在 date sort 中稳定排到最后。

### P2.3 Query execution 集成

在 finder 层支持文本 query：

```lua
require("obsidian-tasks").find_tasks({
  query = [[
    not done
    due on or before 2026-05-20
    sort by due
    group by filename
    limit 20
  ]],
})
```

执行流程：

1. scanner 扫描 vault。
2. query parser 编译 query plan。
3. query executor 应用 filters。
4. sort 模块应用多级排序。
5. limit 在排序后、分组前生效。
6. display 使用 query plan 的 `group_by`。

兼容现有 Lua opts：

- 如果传了 `query`，以 query text 为主。
- `opts.filter` 仍可作为额外 Lua filter 叠加。
- `opts.group_by` 只在 query 里没有 `group by` 时生效。

验收：

- 旧的 `find_tasks({ group_by = ... })` 手测流程继续可用。
- 新的 `find_tasks({ query = ... })` 能返回正确结果。
- `<c-r>` 刷新时保留上一段 query。

### P2.4 Saved queries

在 `setup()` 中支持 named queries：

```lua
require("obsidian-tasks").setup({
  default_query = "inbox",
  queries = {
    inbox = [[
      not done
      sort by due
    ]],
    overdue = [[
      not done
      due before today
      sort by due
    ]],
  },
})
```

建议内部 query source 结构：

```lua
{
  id = "due_soon",
  name = "due_soon",
  query = "...",
  source_type = "config",
  source_path = nil,
  source_line = nil,
}
```

验收：

- `setup({ queries = ... })` 中配置的 query 可以被命令和 picker 发现。
- `default_query` 不存在时给出清晰提示。
- query name 支持 snake_case、kebab-case 和普通字符串显示名。

### P2.5 Global Tasks panel

新增 `lua/obsidian-tasks/panel.lua`，作为日常入口。

建议 API：

```lua
require("obsidian-tasks").open(opts)
require("obsidian-tasks").open_query(name, opts)
require("obsidian-tasks").run_query(query, opts)
```

建议 user commands：

```vim
:ObsidianTasks
:ObsidianTasks inbox
:ObsidianTasks! due_soon
:ObsidianTasksQuery not done
```

命令行为：

- `:ObsidianTasks`：打开 last query 或 default query。
- `:ObsidianTasks name`：打开 named query。
- `:ObsidianTasks! name`：打开 pinned result buffer，不复用 active panel。
- `:ObsidianTasksQuery ...`：执行一行临时 query，主要用于快速验证。

Panel keymaps：

- `o`：打开 query picker。
- `]q`：切到下一个 query。
- `[q`：切到上一个 query。
- `gq`：跳到 query source；Phase 2 中 config query 只提示来源，Phase 3 支持跳到 named block。
- `<space>`：toggle 当前任务。
- `<c-s>`：保存修改回源文件。
- `<c-r>`：刷新当前 query。
- `gd` / `gf`：跳到任务源文件。
- `q`：关闭当前 panel。

Pinned buffer 规则：

- 普通 panel buffer 名称固定为 `obsidian-tasks://active`。
- Pinned buffer 名称使用 query id，例如 `obsidian-tasks://due_soon`。
- 同名 pinned query 已存在时，命令切到已有 buffer 并刷新，而不是重复创建。
- Pinned buffer 可以用普通 Neovim window/tab/buffer 工作流管理。

验收：

- 用户在任意 buffer 执行 `:ObsidianTasks` 都能打开任务面板。
- query picker 能在 config queries 中切换。
- `]q` / `[q` 切换后刷新结果和标题。
- `:ObsidianTasks! query_name` 可以同时保留多个查询结果。
- 结果 buffer 中 toggle/save/jump/refresh 不回归。

### P2.6 Result buffer 可用性增强

在现有 display 上加少量高价值能力：

- 顶部显示当前 query name。
- 顶部显示任务数量。
- limit 生效时显示 `Showing X of Y tasks`。
- query 出错时显示错误 buffer，而不是只 notify。
- 空结果也显示结果 buffer，提示当前 query 没有命中，而不是只 notify。
- 分组支持 date/heading/filename。
- 每条任务仍保留源文件 metadata，`gd/gf` 和保存写回继续可用。

验收：

- 普通结果、空结果、query 错误都能被用户看懂。
- result buffer 中 toggle + save 不因 query mode 失效。
- count 与 limit 行为一致。

### P2.7 测试文档与 smoke tests

新增：

```text
PHASE_2_TEST.md
```

建议同时增加一个 headless smoke test 脚本：

```text
scripts/smoke_phase2.sh
```

测试覆盖：

- query parser 指令解析。
- date helper 校验和比较。
- query execution 过滤、排序、分组、limit。
- saved queries 和 `default_query`。
- `:ObsidianTasks` 打开 active panel。
- pinned query buffer。
- 结果 buffer 中 toggle/save 不回归。

## Phase 2 第一批建议落地需求

第一批不要一次吃完整个 Phase 2，建议先做这 5 个：

1. `query.lua`：支持 `done/not done`、priority、description/tag/path、absolute date filters、sort、group、limit。
2. `date.lua`：支持 `YYYY-MM-DD` 校验比较、`today/tomorrow/yesterday` 和 `happens_date`。
3. finder 集成 `find_tasks({ query = ... })`，并保证旧 opts 兼容。
4. `setup()` 支持 `queries` 和 `default_query`。
5. 增加 `:ObsidianTasks`、`:ObsidianTasksQuery`、`open()`、`run_query()`。

第二批再做：

1. query picker：`o`、`]q`、`[q`。
2. pinned result buffer：`:ObsidianTasks! name`。
3. date/heading/filename grouping。
4. task count、limit count、空结果 buffer、query error buffer。
5. `PHASE_2_TEST.md` 和 smoke test。

## 明确不做范围

- 自动扫描 vault 中的 named `tasks` code block；这放到 Phase 3。
- `run_query_at_cursor()` 和 `:ObsidianTasksRunBlock`；这放到 Phase 3。
- inline preview / virtual lines；这放到 Phase 3 或更后面。
- recurrence 完成后生成下一次任务。
- custom status registry 和 status type。
- 自动 done/cancelled date 写回。
- 编辑 modal。
- auto-suggest。
- Dataview inline field 格式。
- Boolean / regex / function query。

## 完成标准

Phase 2 完成时，应能在任意 buffer 中执行：

```vim
:ObsidianTasks
```

打开默认任务面板；也可以执行：

```vim
:ObsidianTasks due_soon
:ObsidianTasks! inbox
```

打开指定查询或 pinned 查询结果。

同时支持 Lua API：

```lua
require("obsidian-tasks").find_tasks({
  query = [[
    not done
    due on or before 2026-05-20
    priority is above low
    sort by due
    sort by priority
    group by filename
    limit 20
  ]],
})
```

结果 buffer 必须继续支持跳源文件、toggle、保存写回、刷新和 query picker。
