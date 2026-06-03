# Phase 6: Polish, Diagnostics, and Original-Parity Features

目标：在 Phase 5 已经具备高级查询、编辑表单、补全、依赖和 Query File Defaults 的基础上，补齐原版 Obsidian Tasks 中对日常使用影响最大的“可解释、可视化、可调试、生态兼容”能力。

Phase 6 的原则：

- 只做原版 Obsidian Tasks 中确实存在的能力，Neovim 中只做交互适配。
- 每个子阶段都要有独立 `PHASE_6_X.md`、`PHASE_6_X_TEST.md` 和 `scripts/smoke_phase6_x.sh`。
- 不把互相依赖很强的功能塞进同一次提交。每个子阶段完成后先跑本阶段 smoke，再跑最近关键回归。
- 新 agent 接手时，先读本文件、`FEATURES.md`、`PHASE_5.md`，再读对应子阶段引用的源码。

当前仓库上下文：

- Neovim 插件目录：`obsidian-tasks.nvim`
- 原版 Obsidian Tasks 源码目录：`../obsidian-tasks`
- Phase 5 最新完成项：`PHASE_5_10.md`
- Phase 5 最新提交：`1b8873c feat: phase 5 10`
- 关键回归脚本：
  - `scripts/smoke_phase5_10.sh`
  - `scripts/smoke_phase5_9.sh`
  - `scripts/smoke_phase5_8.sh`
  - `scripts/smoke_phase5_3.sh`
  - `scripts/smoke_phase5.sh`
  - `scripts/smoke_phase4.sh`
  - `scripts/smoke_phase2.sh`

## Phase 6 拆分总览

建议顺序：

1. Phase 6.2：Urgency score、`show urgency`、`sort/group by urgency`。Done，详见 `PHASE_6_2.md`。
2. Phase 6 Native Completion Adapter：原生补全 adapter。Done，详见 `PHASE_6_NATIVE_COMPLETION.md`。
3. Phase 6.3：`show tree`、父子 list item 与 sub-items。Done，详见 `PHASE_6_3.md`。
4. Phase 6.4：Toolbar filter/copy 和 result view polishing。Done，详见 `PHASE_6_4.md`。
5. Phase 6.5：Calendar-style date picker、date action menu、postpone/advance polish。Done，详见 `PHASE_6_5.md`。
6. Phase 6.6：Auto-suggest polish 和任务搜索建议。
7. Phase 6.7：Dataview task format MVP。
8. Phase 6.8：Frontmatter properties、links、scripting surface。
9. Phase 6.1：Query diagnostics、`explain` 和错误渲染增强，暂缓。

当前决策：Phase 6.1 先跳过。原因是 query diagnostics 和 `explain` 使用频率低，而且复杂查询写错时更适合到 Obsidian 原版里做权威验证。文档仍保留 6.1 的完整设计，作为后续 backlog。

当前 Phase 6.2、Native Completion Adapter、6.3、6.4、6.5 已完成。下一步优先做 6.6，因为它能在现有补全 adapter 和 dependency editor 基础上继续补齐原版 auto-suggest 的高频体验。Phase 6.7 和 6.8 涉及数据模型扩展，风险更高，建议放后面。

---

## Phase 6.1: Query Diagnostics + Explain

状态：暂缓。除非用户明确需要 Neovim 内解释 query，否则先不要实现。

### 目标

让查询失败和查询解释都像原版一样可读，用户能知道：

- 组合后的最终 query 是什么。
- Global Query、Query File Defaults、当前 tasks block 分别贡献了哪些 instruction。
- placeholders 如何展开。
- 哪一行 query 报错、为什么报错。
- `explain` instruction 不只被 parser 接受，而是能在 result buffer / preview 中显示解释。

### 原版能力

原版支持在 tasks code block 中写：

```tasks
explain
not done
due before tomorrow
```

它会渲染解释文本，说明 global query、query file defaults、当前 code block query 如何被解释。

原版参考：

- `../obsidian-tasks/docs/Queries/Explaining Queries.md`
- `../obsidian-tasks/docs/Scripting/Placeholders.md`
- `../obsidian-tasks/src/Query/Query.ts`
- `../obsidian-tasks/src/Query/Explain/Explainer.ts`
- `../obsidian-tasks/src/Query/Explain/Explanation.ts`
- `../obsidian-tasks/src/Query/QueryRendererHelper.ts`
- `../obsidian-tasks/src/Renderer/QueryResultsRendererBase.ts`

### 当前状态

已存在：

- `lua/obsidian-tasks/query.lua`
  - 已识别 `explain`。
  - `plan.explain = true`。
  - `plan.layout.explain = true`。
  - query errors 已有结构化 `line_number`、`line`、`message`。
- `lua/obsidian-tasks/display.lua`
  - 已有 `display_query_errors()`，但信息偏少。
- `lua/obsidian-tasks/finder.lua`
  - query parse error 时会打开 error buffer。
- `lua/obsidian-tasks/preview.lua`
  - preview 遇到 query error 只展示第一条错误。

缺口：

- `explain` 不渲染任何解释内容。
- 错误 buffer 没显示最终 composed query、global/defaults/source 分段。
- preview 不显示 explain，也不显示完整错误上下文。
- filter/sort/group/layout/limit 没有 explain 文本。

### Neovim 设计

新增一个轻量 explain 模块：

```text
lua/obsidian-tasks/explain.lua
```

建议 API：

```lua
local explain = require("obsidian-tasks.explain")

explain.lines(plan, opts) -> string[]
explain.error_lines(errors, opts) -> string[]
explain.composition_lines(composition) -> string[]
```

输出面向 result buffer 和 preview，先做纯文本，不做 fancy UI。

Result buffer 里，如果 query 包含 `explain`：

```text
Tasks: Project Open
Source: block Dashboard.md#L10

Query explanation:

Global Query:
  description does not include GlobalHidden

Query File Defaults:
  folder includes /vault/Projects/
  short mode
  show task count

Tasks block query:
  not done
  sort by filename

Filters:
  - not done
  - description does not include GlobalHidden

Sorting:
  - filename ascending

Layout:
  - short mode
  - show task count
```

Error buffer 里补：

```text
Tasks: Project Open
Source: block Dashboard.md#L10

Query errors:

- line 4: Unsupported query instruction
  frobnicate tasks

Composed query:

Global Query:
...

Query File Defaults:
...

Tasks block query:
...
```

Inline preview 遇到 `explain` 时建议只展示前几行摘要，避免 virtual lines 过长：

```text
Tasks preview: Query explanation available
  Filters: 2, Sorts: 1, Groups: 0, Layout: 2
```

### 实现建议

涉及文件：

- 新增：`lua/obsidian-tasks/explain.lua`
- 修改：`lua/obsidian-tasks/display.lua`
- 修改：`lua/obsidian-tasks/preview.lua`
- 修改：`lua/obsidian-tasks/finder.lua`，如需要把更多 opts 传给 display。
- 可能修改：`lua/obsidian-tasks/query.lua`，为 filter/sort/group/layout 增加 `line` 或标准 explain fields。

实现步骤：

1. 先做 composition 分段输出。
2. 再做 plan 摘要：
   - filter type -> human text
   - sort field/reverse -> human text
   - group fields -> human text
   - layout statements -> human text
   - limit/group limit -> human text
3. `display.display_tasks()` 在 header 后、task lines 前插入 explain block。
4. `display.display_query_errors()` 使用 `explain.error_lines()`。
5. preview 对 `plan.explain` 返回摘要。

### 验收

- `explain` query 能在 result buffer 里显示解释文本。
- 解释内容能区分 Global Query、Query File Defaults、当前 block query。
- placeholder 展开后的 query 能被展示。
- query error buffer 包含错误行、错误信息和 composed query。
- preview 不因 `explain` 出现大量 virtual lines，也不报错。
- 不影响没有 `explain` 的普通查询。

### Smoke 建议

新增：

```sh
scripts/smoke_phase6_1.sh
```

覆盖：

- 有 global query + query file defaults + block query + `explain`。
- 有 `{{query.file.folder}}` placeholder。
- 有 unsupported instruction 触发 error buffer。
- 有 preview refresh。
- 断言 result buffer 中包含 `Query explanation:`、`Global Query:`、`Query File Defaults:`、`Tasks block query:`。

回归：

```sh
sh scripts/smoke_phase5_10.sh
sh scripts/smoke_phase5_3.sh
sh scripts/smoke_phase5.sh
```

---

## Phase 6.2: Urgency Score + Urgency Layout

状态：已实现，详见 `PHASE_6_2.md` 和 `PHASE_6_2_TEST.md`。

### 目标

实现原版 Tasks 的 urgency 计算，并让这些 query/layout 可用：

```tasks
sort by urgency
group by urgency
show urgency
hide urgency
```

同时让 `task.urgency` 可在 Lua function filter 中读取。

### 原版能力

原版 urgency 是一个数值分数，用 priority、due、scheduled、start 等信息计算任务紧迫程度。默认排序中也会使用 urgency。

原版参考：

- `../obsidian-tasks/docs/Advanced/Urgency.md`
- `../obsidian-tasks/docs/Queries/Layout.md`
- `../obsidian-tasks/src/Task/Urgency.ts`
- `../obsidian-tasks/src/Query/Filter/UrgencyField.ts`
- `../obsidian-tasks/src/Query/Sort/Sort.ts`
- `../obsidian-tasks/src/Layout/QueryLayout.ts`
- `../obsidian-tasks/src/Renderer/HtmlQueryResultsRenderer.ts`

### 当前状态

已存在：

- `show/hide urgency` 已被 parser 接受为 layout field。
- `FEATURES.md` 中标记 urgency 未实现。

缺口：

- task model 没有 `urgency`。
- sort/group fields 是否支持 `urgency` 需检查 `lua/obsidian-tasks/query.lua` 和 `sort.lua`。
- result buffer 不显示 urgency。
- function filter 读不到 `task.urgency`。

### Neovim 设计

新增：

```text
lua/obsidian-tasks/urgency.lua
```

建议 API：

```lua
urgency.score(task, opts) -> number
urgency.enrich(task, opts) -> task
urgency.format(task) -> string
```

显示格式：

- full mode：`urgency 8.80`
- short mode：`8.80`
- 若 `hide urgency`：不显示。

计算策略：

- 第一版优先按原版文档和 `src/Task/Urgency.ts` 迁移公式。
- 如果迁移完整公式太大，Phase 6.2 也要至少保留同名 API 和 smoke，文档写清楚哪些权重已覆盖。
- 不能把 urgency 设计成自创评分；公式必须来源于原版源码或 docs。

### 实现建议

涉及文件：

- 新增：`lua/obsidian-tasks/urgency.lua`
- 修改：`lua/obsidian-tasks/task.lua`，parse 后 enrich `task.urgency`。
- 修改：`lua/obsidian-tasks/scanner.lua`，如 urgency 需要 today/config，可在 scan 后 enrich。
- 修改：`lua/obsidian-tasks/query.lua`，支持 `sort/group by urgency`。
- 修改：`lua/obsidian-tasks/sort.lua`，urgency 降序排序。
- 修改：`lua/obsidian-tasks/parser.lua`，group by urgency。
- 修改：`lua/obsidian-tasks/display.lua` 和 `preview.lua`，显示 urgency。

注意：

- urgency 应依赖可配置 `today`，smoke 中使用固定日期。
- 不要让不同日期运行 smoke 结果不稳定。
- 原版文档说 urgency 不考虑 task status 和 dependencies，除非原版后续源码不同，否则保持一致。

### 验收

- task parse 后有 numeric `task.urgency`。
- `show urgency` 在 result buffer 显示分数。
- `hide urgency` 隐藏分数。
- `sort by urgency` 按高分在前排序。
- `group by urgency` 可生成分组 heading。
- `filter by function task.urgency > ...` 可用。
- short mode 和 hide/show metadata 不冲突。

### Smoke 建议

新增：

```sh
scripts/smoke_phase6_2.sh
```

测试数据：

```markdown
- [ ] #task Highest due today 🔺 📅 2026-05-16
- [ ] #task Low later 🔽 📅 2026-06-16
- [ ] #task No date
```

覆盖：

- fixed today：`2026-05-16`
- `show urgency`
- `sort by urgency`
- `group by urgency`
- `filter by function task.urgency > 1`

回归：

```sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase5.sh
sh scripts/smoke_phase4.sh
```

---

## Phase 6.3: Show Tree + Sub-Items

### 目标

实现 `show tree` / `hide tree` 的实际结果展示：查询命中任务时，按原文件中的 list 层级显示父级 list item、父任务和子任务，而不是只显示扁平任务行。

### 原版能力

原版可以展示匹配任务及其相关 list tree，让用户保留上下文。

原版参考：

- `../obsidian-tasks/docs/Queries/Layout.md`
- `../obsidian-tasks/docs/Queries/About Queries.md`
- `../obsidian-tasks/src/Task/ListItem.ts`
- `../obsidian-tasks/src/Task/Task.ts`
- `../obsidian-tasks/src/Layout/TaskLayout.ts`
- `../obsidian-tasks/src/Renderer/TaskLineRenderer.ts`
- `../obsidian-tasks/src/Query/Filter/ExcludeSubItemsField.ts`

### 当前状态

已存在：

- scanner 已跳过 fenced code block。
- task model 保存 `indentation`、`list_marker`、`line_number`。
- layout parser 已接受 `show tree` / `hide tree`。

缺口：

- scanner 没有构建 list item tree。
- task 没有 parent/children/sibling context。
- display 仍是扁平 list。
- `exclude sub-items` filter 未实现。

### Neovim 设计

先做 MVP：

- 扫描单个文件时，记录所有 list items，不只 task。
- 根据缩进和 list marker 建立 parent/children。
- 每个 task 带：
  - `parent`
  - `children`
  - `list_path`
  - `tree_lines`
- `show tree` 时，result buffer 中对每个命中 task 显示：
  - 必要父级 list item。
  - 命中 task 本身。
  - 子 list item / 子 task。
- 仍保持每个可编辑 task 有唯一 index，父级非 task 行不参与 toggle/save。

建议显示：

```text
1. [ ] Parent project
   - [ ] Matched child task [[file#L10]]
     - supporting sub item
     - [ ] nested child task
```

如果多个命中任务共享父级，第一版可以允许重复树上下文；后续再去重。

### 实现建议

涉及文件：

- 修改：`lua/obsidian-tasks/scanner.lua`
- 修改：`lua/obsidian-tasks/task.lua`
- 修改：`lua/obsidian-tasks/display.lua`
- 修改：`lua/obsidian-tasks/query.lua`，支持 `exclude sub-items`。
- 修改：`lua/obsidian-tasks/parser.lua`，如果 group/display 需要识别 tree lines。

实现步骤：

1. 在 scanner 中增加 `scan_file_with_items()` 或扩展 `scan_file()` 返回 task 时带 list context。
2. 识别 list item：
   - `- text`
   - `* text`
   - `+ text`
   - `1. text`
   - `1) text`
   - blockquote 前缀可先保留在 indentation 中。
3. 用缩进宽度维护 stack。
4. 对 task 保存 parent/children line refs。
5. display 根据 `layout.show.tree` 决定是否调用 `format_task_tree_for_display()`。
6. 非 task tree context 行不要写入 `core.task_index_map`。

### 验收

- 默认仍是扁平显示。
- `show tree` 显示父子上下文。
- `hide tree` 显式关闭 tree。
- `gd/gf` 对命中 task 仍跳转正确。
- `<space>` / `e` / `s` / `p` 只作用于 task index 行。
- `exclude sub-items` 可以排除子任务或至少被 parser 接受并正确过滤常见子任务。

### Smoke 建议

新增：

```sh
scripts/smoke_phase6_3.sh
```

测试数据：

```markdown
- [ ] #task Parent
  - [ ] #task Child target
    - plain note
    - [ ] #task Grandchild
- [ ] #task Sibling
```

覆盖：

- `description includes Child`
- `show tree`
- `hide tree`
- `exclude sub-items`
- result line mapping 不错位。

回归：

```sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase4.sh
sh scripts/smoke_phase2.sh
```

---

## Phase 6.4: Toolbar + Result View Polish

### 目标

补齐原版查询结果顶部 toolbar 的 Neovim 等价能力：

- 临时 description filter。
- 复制当前查询结果为 Markdown。
- obey `show toolbar` / `hide toolbar`。
- 更清晰的 result buffer header。

### 原版能力

原版 result UI 顶部有 toolbar，可用于临时过滤和复制结果。

原版参考：

- `../obsidian-tasks/docs/Queries/Layout.md`
- `../obsidian-tasks/src/Layout/QueryLayoutOptions.ts`
- `../obsidian-tasks/src/Layout/QueryLayout.ts`
- `../obsidian-tasks/src/Renderer/HtmlQueryResultsRenderer.ts`
- `../obsidian-tasks/src/Renderer/Renderer.scss`
- `../obsidian-tasks/src/Query/Presets/Presets.ts`

### 当前状态

已存在：

- `show/hide toolbar` 已被 parser 接受。
- result buffer header 有 query picker、refresh、jump、edit、postpone 等帮助行。

缺口：

- toolbar directive 不改变 UI。
- 没有临时 filter。
- 没有 copy result 命令。

### Neovim 设计

`show toolbar` 时，header 中增加一行可操作命令提示：

```text
Toolbar: / filter description   y copy markdown   Y copy with backlinks   c clear filter
```

交互：

- `/` 或 `f`：输入临时 description filter，只过滤当前 result buffer，不改 query source。
- `c`：清空临时 filter。
- `y`：复制当前可见 task lines 为 Markdown checklist，不包含 result index。
- `Y`：复制当前可见 task lines，包含 source backlink。

如果用户已有 `/` 搜索习惯冲突，优先用 `f`，`/` 可不绑定。

### 实现建议

涉及文件：

- 修改：`lua/obsidian-tasks/display.lua`
- 可能新增：`lua/obsidian-tasks/toolbar.lua`

实现细节：

- 在 `M.buffer_finder_opts[buf]` 中保存 `toolbar_filter`。
- filter 只影响显示层，不重新扫描 vault。
- 复制结果基于 `core.task_index_map[buf]` 和当前 layout 格式化。
- `hide toolbar` 时不显示 toolbar 提示，但可以保留 commands 不绑定。

### 验收

- `show toolbar` 显示 toolbar 行。
- `hide toolbar` 隐藏 toolbar 行。
- 临时 filter 可缩小当前结果。
- 清空 filter 后恢复当前 query 结果。
- copy markdown 内容可放入 unnamed register。
- 不破坏 `<c-r>` refresh、query picker 和 task mapping。

### Smoke 建议

新增：

```sh
scripts/smoke_phase6_4.sh
```

覆盖：

- `show toolbar`
- `hide toolbar`
- 调用 toolbar filter API，不必模拟 UI input。
- 验证复制函数返回 markdown lines。

回归：

```sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase5_9.sh
```

---

## Phase 6.5: Calendar Date Picker + Date Menus

状态：已实现，详见 `PHASE_6_5.md` 和 `PHASE_6_5_TEST.md`。

### 目标

把 Phase 5.9 的 date picker 从“常用日期列表 + custom input”升级为更接近原版 date menu 的 Neovim 体验：

- Calendar-style month grid。
- 可选择 due/start/scheduled/done/cancelled/created。
- 可 clear。
- 可 postpone/advance 当前日期。
- 可从普通 Markdown task 行和 form buffer 使用。

### 原版能力

原版有日期编辑菜单和 date picker UI，右键日期或编辑 modal 日期字段都能选择/修改日期。

原版参考：

- `../obsidian-tasks/docs/Editing/Editing Dates.md`
- `../obsidian-tasks/src/ui/Menus/DatePicker.ts`
- `../obsidian-tasks/src/ui/Menus/DateMenu.ts`
- `../obsidian-tasks/src/ui/DateEditor.svelte`
- `../obsidian-tasks/src/DateTime/Postponer.ts`

### 当前状态

已存在：

- `lua/obsidian-tasks/date_picker.lua`
  - `Clear`
  - `Today`
  - `Tomorrow`
  - `Yesterday`
  - `Next week`
  - `Next month`
  - `Custom...`
- `:ObsidianTasksPickDate [field]`
- form buffer `gd`
- ordinary task line date mutation。

缺口：

- 没有 calendar grid。
- 没有 advance/postpone menu。
- 没有显示当前 field/current date。
- 没有键盘导航。

### Neovim 设计

先做 floating buffer calendar：

```text
obsidian-tasks://date-picker

May 2026        field: due
Mo Tu We Th Fr Sa Su
             1  2  3
 4  5  6  7  8  9 10
11 12 13 14 15 [16]17
18 19 20 21 22 23 24
25 26 27 28 29 30 31

h/l prev/next day  j/k week  H/L month  <CR> select  c clear  q close
```

API：

```lua
date_picker.open_calendar(opts)
date_picker.pick_at_cursor({ field = "due", calendar = true })
date_picker.pick_for_form(buf, field, opts)
```

保持旧 `vim.ui.select` picker 可用：

```lua
setup({
  date_picker = {
    style = "select", -- or "calendar"
  },
})
```

### 实现建议

涉及文件：

- 修改：`lua/obsidian-tasks/date_picker.lua`
- 修改：`lua/obsidian-tasks/edit.lua`
- 修改：`lua/obsidian-tasks/panel.lua`，命令可加 bang 或 opts。
- 可能新增：`lua/obsidian-tasks/calendar.lua`

实现细节：

- 日期计算使用现有 `lua/obsidian-tasks/date.lua`。
- smoke 固定 today，避免日期漂移。
- Calendar buffer 只负责选择日期，实际写回继续调用 `set_date_at_cursor()` 或 form setter。

### 验收

- 普通 task 行可打开 calendar 并写入 due/scheduled/start。
- form 日期字段可打开 calendar 并写回字段值。
- clear 可移除日期。
- month navigation 正确跨月。
- 旧 select picker 不被破坏。

### Smoke 建议

新增：

```sh
scripts/smoke_phase6_5.sh
```

覆盖纯函数优先：

- month grid generation。
- cursor date movement。
- select date callback。
- clear callback。
- `set_date_at_cursor()` 回归。

回归：

```sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase5_5.sh
```

---

## Phase 6.6: Auto-Suggest Polish + Task Search Suggestions

### 目标

补齐原版 auto-suggest 中最影响效率的部分：

- dependency/id suggestions 能搜索 vault tasks。
- date suggestions 根据当前输入更智能。
- recurrence/onCompletion/status/priority suggestions 在 form 和普通 task 行中保持一致。
- `nvim-cmp` source 与手动 completion 继续共享同一套 core。

### 原版能力

原版编辑任务时会按上下文建议 emoji、日期、recurrence、id/dependsOn、onCompletion 等。

原版参考：

- `../obsidian-tasks/docs/Editing/Auto-Suggest.md`
- `../obsidian-tasks/src/Commands/CreateOrEditTaskParser.ts`
- `../obsidian-tasks/src/ui/EditTask.svelte`
- `../obsidian-tasks/src/ui/EditInstructions`

### 当前状态

已存在：

- Phase 5.6 form auto-suggest MVP。
- Phase 5.7 completion core + ordinary Markdown task adapter。
- Phase 5.8 optional `nvim-cmp` source。
- Phase 5.9 dependency editor 可选择任务。

缺口：

- 补全列表中的 dependency/id 还不完整。
- 任务搜索建议和 dependency editor 没完全复用。
- 普通 buffer 中上下文识别还比较保守。
- Dataview format 的补全要等 Phase 6.7 后再接。

### Neovim 设计

增强 `completion.lua`，不要把逻辑写进 cmp source：

```lua
completion.suggest(ctx) -> items
completion.task_id_items(opts) -> items
completion.date_items(prefix, opts) -> items
completion.recurrence_items(prefix, opts) -> items
```

dependency suggestions：

- 从 `scanner.scan_vault()` 取 tasks。
- label 包含 description、file、line、id。
- 如果 task 没 id，completion item 可以提供 `data = { needs_id = true }`，但实际写回不应在普通 completion confirm 里自动修改其它文件，避免副作用。
- 真正自动补 id 仍由 `ObsidianTasksAddDependency` / form `gD` 做。

### 实现建议

涉及文件：

- 修改：`lua/obsidian-tasks/completion.lua`
- 修改：`lua/obsidian-tasks/completion/cmp.lua`
- 修改：`lua/obsidian-tasks/dependency_editor.lua`
- 修改：`lua/obsidian-tasks/edit.lua`

验收重点：

- 不破坏用户已有 `nvim-cmp`。
- 普通 Markdown task 行只在 task context 中给建议。
- form buffer 中仍可 `<C-X><C-U>`。
- backspace 问题不能复发；补全不应创建不可删除的隐藏文本。

### Smoke 建议

新增：

```sh
scripts/smoke_phase6_6.sh
```

回归必须跑：

```sh
sh scripts/smoke_phase5_8.sh
sh scripts/smoke_phase5_7.sh
sh scripts/smoke_phase5_6.sh
sh scripts/smoke_phase5_9.sh
```

---

## Phase 6.7: Dataview Task Format MVP

### 目标

支持原版 Tasks 的 Dataview inline field 格式读写 MVP：

```markdown
- [ ] #task Write docs [due:: 2026-05-20] [priority:: high]
- [ ] #task Blocked [id:: alpha] [dependsOn:: beta]
```

第一版目标是“可解析、可查询、编辑保存时尽量保留格式”，不是一次性覆盖所有 Dataview 语法。

### 原版能力

原版支持 Tasks Emoji Format 和 Dataview Format，并且设置中一次只选择一种 task format。

原版参考：

- `../obsidian-tasks/docs/Reference/Task Formats/Dataview Format.md`
- `../obsidian-tasks/docs/Reference/Task Formats/About Task Formats.md`
- `../obsidian-tasks/src/TaskSerializer/DataviewTaskSerializer.ts`
- `../obsidian-tasks/src/TaskSerializer/DefaultTaskSerializer.ts`
- `../obsidian-tasks/src/TaskSerializer/index.ts`
- `../obsidian-tasks/docs/Other Plugins/Dataview.md`

### 当前状态

已存在：

- Emoji format parser/serializer。
- `setup(config)` 已有集中配置入口。

缺口：

- 不解析 `[due:: ...]` 等 inline fields。
- serializer 不知道 Dataview format。
- edit form、date picker、dependency editor 都写 emoji。

### Neovim 设计

新增配置：

```lua
require("obsidian-tasks").setup({
  task_format = "tasks", -- "tasks" | "dataview"
})
```

兼容 camelCase：

```lua
taskFormat = "dataview"
```

第一版字段映射：

| Tasks field | Emoji | Dataview key |
| --- | --- | --- |
| priority | `🔺` 等 | `priority` |
| created | `➕` | `created` |
| start | `🛫` | `start` |
| scheduled | `⏳` | `scheduled` |
| due | `📅` | `due` |
| done | `✅` | `completion` 或 `done`，实现前需按原版确认 |
| cancelled | `❌` | `cancelled` |
| id | `🆔` | `id` |
| dependsOn | `⛔` | `dependsOn` |
| onCompletion | `🏁` | `onCompletion` |

实现前必须确认原版 Dataview key 名称，不要凭印象写。

### 实现建议

涉及文件：

- 修改：`lua/obsidian-tasks/init.lua`，接受 `task_format` / `taskFormat`。
- 修改：`lua/obsidian-tasks/task.lua`，拆 parser/serializer strategy。
- 修改：`lua/obsidian-tasks/mutation.lua`，保持格式写回。
- 修改：`lua/obsidian-tasks/edit.lua`。
- 修改：`lua/obsidian-tasks/date_picker.lua`。
- 修改：`lua/obsidian-tasks/dependency_editor.lua`。
- 修改：`lua/obsidian-tasks/completion.lua`，Dataview 格式下补 `[field:: value]`。

建议先抽象：

```lua
lua/obsidian-tasks/format/tasks_emoji.lua
lua/obsidian-tasks/format/dataview.lua
```

但不要过度重构。第一步也可以在 `task.lua` 中局部实现，等 smoke 稳定后再拆。

### 验收

- `task_format = "dataview"` 时能解析 due/priority/id/dependsOn。
- 查询 `due before ...`、`priority is high`、`has id` 对 Dataview task 生效。
- toggle done 不破坏 inline fields。
- date picker 写 Dataview field，不写 emoji。
- dependency editor 写 `[dependsOn:: id]`。
- 默认 `task_format = "tasks"` 行为无回归。

### Smoke 建议

新增：

```sh
scripts/smoke_phase6_7.sh
```

回归必须跑：

```sh
sh scripts/smoke_phase5_9.sh
sh scripts/smoke_phase5_5.sh
sh scripts/smoke_phase4.sh
sh scripts/smoke_phase5.sh
```

---

## Phase 6.8: Frontmatter Properties + Links + Scripting Surface

### 目标

扩展 task/query scripting surface，让 Lua function filters 更接近原版 JS custom filters 可读取的数据：

- `task.file` 已有基础字段，继续补 frontmatter/properties。
- `task.frontmatter` / `task.properties`。
- `task.outlinks` / `task.links`。
- `query.file` 已有基础字段，继续补 aliases/tags/classes 等 frontmatter 信息。

### 原版能力

原版 custom filters/sorts/groups 可访问 task、query、file、frontmatter、links 等丰富对象。

原版参考：

- `../obsidian-tasks/docs/Scripting/Task Properties.md`
- `../obsidian-tasks/docs/Scripting/Query Properties.md`
- `../obsidian-tasks/docs/Scripting/JavaScript in Tasks Queries.md`
- `../obsidian-tasks/docs/Getting Started/Obsidian Properties.md`
- `../obsidian-tasks/src/Scripting/TaskExpression.ts`
- `../obsidian-tasks/src/Scripting/TasksFile.ts`
- `../obsidian-tasks/src/Scripting/QueryContext.ts`
- `../obsidian-tasks/src/Task/Link.ts`
- `../obsidian-tasks/src/Task/LinkResolver.ts`

### 当前状态

已存在：

- `task.file` 基础字段：
  - `path`
  - `path_without_extension`
  - `root`
  - `folder`
  - `filename`
  - `filename_without_extension`
- `query.file` placeholder context 已有基础字段。
- Query File Defaults 有轻量 frontmatter parser。

缺口：

- 没有读取普通 note frontmatter 给 task。
- 没有解析 wikilinks/markdown links。
- function filter 里无法基于 file property 过滤。

### Neovim 设计

新增：

```text
lua/obsidian-tasks/frontmatter.lua
lua/obsidian-tasks/links.lua
```

frontmatter 第一版支持：

- YAML block delimiters `---` / `---` 或 `...`
- scalar：
  - string
  - quoted string
  - boolean
  - number
  - null
- simple arrays：
  - `[a, b]`
  - `tags:` followed by `- item`

links 第一版支持：

- wikilink：`[[Note]]`、`[[Note#Heading]]`、`[[Note|Alias]]`
- markdown link：`[label](path.md)`
- task line links。

不要试图完整实现 YAML。复杂 YAML 可以保留原始字符串或忽略，并在文档说明。

### 实现建议

涉及文件：

- 新增：`lua/obsidian-tasks/frontmatter.lua`
- 新增：`lua/obsidian-tasks/links.lua`
- 修改：`lua/obsidian-tasks/scanner.lua`，scan_file 时读取一次 file metadata，注入每个 task。
- 修改：`lua/obsidian-tasks/task.lua`，task fields 增加 frontmatter/links。
- 修改：`lua/obsidian-tasks/query.lua`，function filter context 扩展。
- 可能复用/迁移：`lua/obsidian-tasks/query_file_defaults.lua` 的 frontmatter parser，避免两套规则不一致。

### 验收

- task function filter 可用：

```tasks
filter by function task.frontmatter.area == "work"
filter by function vim.tbl_contains(task.file.tags or {}, "project")
filter by function #(task.links or {}) > 0
```

- query placeholders 不回归。
- Query File Defaults 读取不回归。
- 没有 frontmatter 的文件不报错。

### Smoke 建议

新增：

```sh
scripts/smoke_phase6_8.sh
```

回归：

```sh
sh scripts/smoke_phase5_3.sh
sh scripts/smoke_phase5_10.sh
sh scripts/smoke_phase5.sh
```

---

## Phase 6 之后暂不建议放入本阶段的内容

这些是原版存在或生态相关，但建议留到 Phase 7+，避免 Phase 6 膨胀：

- Vault-wide cache 和增量更新。
- 完整 recurrence grammar。
- 完整 custom sort/group by Lua function。
- 完整 i18n。
- 完整 Obsidian CSS/highlight parity。
- QuickAdd/Kanban/Meta Bind 等外部插件适配。
- 真正的 Obsidian-style inline block rendering。

## 每个子阶段的交付格式

实现任一 Phase 6.x 时，建议按这个清单交付：

1. 新增 `PHASE_6_X.md`：写清目标、原版依据、设计、边界、验收。
2. 新增 `PHASE_6_X_TEST.md`：写手动测试步骤。
3. 新增 `scripts/smoke_phase6_x.sh`：headless smoke。
4. 更新 `FEATURES.md` 对应 feature 状态。
5. 更新 `PHASE_6.md` 中该子阶段状态。
6. 跑本阶段 smoke 和相关回归。
7. `git diff --check`。

## 推荐下一步

建议下一步做 **Phase 6.6 Auto-Suggest Polish + Task Search Suggestions**。

理由：

- Phase 6.5 已经补完 calendar date picker，日期编辑的主路径先闭环。
- Phase 6 Native Completion Adapter 已经接上原生补全，Phase 6.6 可以继续补任务搜索建议和上下文建议质量。
- dependency editor 已有搜索与写回基础，下一步把它接入 auto-suggest 能明显减少手动输入 id/dependsOn 的成本。
