# Phase 3: Named Query Blocks + Preview UX

目标：在 Phase 2 的查询语言和全局 Tasks panel 基础上，把 Markdown 中的 `tasks` code block 变成可自动发现、可选择、可跳转的 named query，并补上轻量 inline preview。

Phase 2 解决“我在任意位置怎么快速打开任务面板”；Phase 3 解决“我的查询定义怎么跟 note 一起存在，并且不用每次手动定位 block”。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_3_TEST.md`，headless smoke 见 `scripts/smoke_phase3.sh`。

已覆盖：

- `query_block.lua`：扫描 `tasks` fenced block，支持 backticks/tildes，解析 `# name:` / `# id:`。
- `query_registry.lua`：合并 config query、block query、recent query，并做轻量缓存。
- picker 展示 config/block/recent query source。
- `gq` 跳回 block query 的 source line。
- `:ObsidianTasksRefreshQueries`。
- `run_query_at_cursor()` 和 `:ObsidianTasksRunBlock`。
- 只读 inline preview：`:ObsidianTasksPreviewToggle` / `:ObsidianTasksPreviewRefresh`。

仍留到后续打磨：

- 更完整的冲突提示和 source-qualified id 交互。
- 保存 Markdown 文件后 debounce 刷新当前文件中的 query blocks。
- preview 样式和可配置字段继续打磨。

## 核心交互模型

用户可以在任意 Markdown 文件里写 named query block：

````markdown
```tasks
# name: Due soon
# id: due-soon
not done
due on or before 2026-05-20
sort by due
group by filename
```
````

然后在任意位置执行：

```vim
:ObsidianTasks
```

在 picker 中看到：

```text
config: inbox
config: due_soon
block: Due soon                 Dashboard.md#L42
block: Weekly review tasks       Weekly.md#L18
```

打开结果后：

- `gq` 可以跳到这个 query block 的定义位置。
- `]q` / `[q` 可以在 config query 和 block query 之间切换。
- `<c-r>` 会刷新当前 query 的任务结果。
- `:ObsidianTasksRefreshQueries` 可以重新扫描 named query blocks。

## 为什么放到 Phase 3

- named block discovery 需要扫描 vault 中的 fenced code block，这和 task scanner 相似但语义不同，适合单独实现和测试。
- query registry 会引入 source id、冲突处理、跳转定义等交互细节，放进 Phase 2 会让第一批需求过重。
- inline preview 适合在 query/panel 稳定后做，否则会把展示层和查询层一起搅动。

## Phase 3 范围

### P3.1 Query block scanner

新增模块：

```text
lua/obsidian-tasks/query_block.lua
lua/obsidian-tasks/query_registry.lua
```

扫描 vault 中 `.md` 文件的 fenced code block，只处理 info string 为 `tasks` 的 block：

````markdown
```tasks
not done
sort by due
```
````

支持 fence：

- 三个或更多 backticks。
- 三个或更多 tildes。
- info string 中第一个 token 为 `tasks`。

block metadata：

- `# name: Due soon`
- `# id: due-soon`

这些 metadata 行仍然是 query parser 的注释行，不参与 filter。

输出 query source：

```lua
{
  id = "due-soon",
  name = "Due soon",
  query = "not done\nsort by due",
  source_type = "block",
  source_path = "/vault/Dashboard.md",
  source_line = 42,
  end_line = 49,
}
```

id 规则：

- 如果写了 `# id:`，优先使用它。
- 如果没有 id，但写了 `# name:`，用 name 生成 slug。
- 如果都没有，用 `file_path:start_line` 生成稳定 fallback id，但 picker 中标记为 unnamed。

验收：

- 能发现 vault 中所有 named `tasks` block。
- fenced code block 嵌套文本不会误识别。
- `# name:` / `# id:` 不影响 query parser。
- 发现结果包含文件路径和起始行，用于 `gq` 跳转。

### P3.2 Query registry merge

Phase 3 中 query 来源包括：

- config queries：来自 `setup({ queries = ... })`。
- block queries：来自 vault 中的 named `tasks` block。
- recent transient queries：来自 `:ObsidianTasksQuery ...`。

合并规则：

- config query 和 block query 都显示在 picker 中。
- id 冲突时，保留全部来源，但 picker 显示 source label，例如 `config: due_soon`、`block: due_soon`。
- API 通过 plain id 打开 query 时，优先 config query；如果存在冲突，提示用户使用 source-qualified id。
- source-qualified id 形如 `config:due_soon`、`block:due_soon:/vault/Dashboard.md:42`。

验收：

- picker 能展示不同来源。
- id 冲突不会让 query 丢失。
- `:ObsidianTasks block:...` 可以打开指定 block query。

### P3.3 Query picker 升级

Phase 2 的 picker 只需要列 config queries。Phase 3 将 picker 升级为全来源查询入口。

Picker item 显示：

```text
Due soon                    block   Dashboard.md#L42
inbox                       config
last manual query           recent
```

行为：

- 选择后刷新 active panel。
- 在 pinned panel 中选择 query，只刷新当前 pinned buffer。
- 支持显示 query source path。
- `gq` 对 block query 跳到源文件行；对 config query 显示来源提示；对 recent query 打开临时 query buffer。

验收：

- 不需要先定位文件或 block，也能打开任意 named block query。
- 从结果 buffer 可以跳回 query 定义。
- query block 改动后，刷新 registry 能看到新结果。

### P3.4 Run block at cursor

新增辅助入口：

```lua
require("obsidian-tasks").run_query_at_cursor(opts)
```

User command：

```vim
:ObsidianTasksRunBlock
```

行为：

- 光标在 `tasks` fenced block 内时，收集 block query 并运行。
- 光标不在 `tasks` block 内时，给出明确提示。
- 如果 block 有 `# name:` / `# id:`，结果 panel 使用对应 query source。
- 如果 block 未命名，则作为 transient query 运行。

这个入口是“开发和调试当前 block”的快捷方式，不是主要日常入口。

验收：

- 在 Markdown 文件中的 `tasks` code block 内执行命令，可以打开查询结果。
- 未命名 block 也能临时运行。
- 不在 block 内执行不会误扫全文件。

### P3.5 Inline preview MVP

Inline preview 是可选增强，不作为主要操作面。

建议先做只读 preview：

- 在 `tasks` block 下方用 virtual lines 显示 summary。
- 默认只显示 count 和前 N 条任务。
- 不在 preview 中支持 toggle/save/edit。
- 真正操作仍然按回车或命令进入 Tasks panel。

示例：

```text
Tasks preview: Showing 5 of 18
  [ ] Finish query parser                 Project.md#L18
  [ ] Write Phase 2 tests                  Daily.md#L7
```

建议命令：

```vim
:ObsidianTasksPreviewToggle
:ObsidianTasksPreviewRefresh
```

验收：

- preview 不修改 Markdown buffer 内容。
- 大文件中可关闭 preview。
- preview 结果和同 query 的 panel 结果一致。

### P3.6 Registry cache

为了避免每次打开 picker 都全量扫描 vault，增加轻量缓存：

- 启动后 lazy scan query blocks。
- `:ObsidianTasksRefreshQueries` 手动刷新。
- 保存 Markdown 文件后，可选 debounce 刷新当前文件中的 query blocks。

验收：

- 大 vault 中 picker 打开不明显卡顿。
- 手动刷新后能看到新增/删除/改名的 query block。
- 查询结果刷新和 query registry 刷新是两个独立概念。

### P3.7 测试文档与 smoke tests

新增：

```text
PHASE_3_TEST.md
```

测试覆盖：

- named `tasks` block 扫描。
- id/name/fallback id。
- query registry merge 和冲突处理。
- picker 展示 source。
- `gq` 跳 query source。
- `run_query_at_cursor()`。
- inline preview 不修改 buffer。

## Phase 3 第一批建议落地需求

第一批：

1. `query_block.lua`：扫描 `tasks` fenced block，解析 `# name:` / `# id:`。
2. `query_registry.lua`：合并 config queries 和 block queries。
3. picker 展示 block queries。
4. `gq` 跳到 block query source。
5. `:ObsidianTasksRefreshQueries`。

第二批：

1. `run_query_at_cursor()` 和 `:ObsidianTasksRunBlock`。
2. unnamed block transient query。
3. recent transient query。
4. inline preview MVP。
5. `PHASE_3_TEST.md` 和 smoke test。

## 明确不做范围

- Obsidian-style 原地替换 code block 内容。
- 在 inline preview 中直接编辑任务。
- Query File Defaults、presets、placeholders。
- Boolean / regex / function query。
- recurrence/custom status/edit modal 等任务语义增强。

这些留到更后面的阶段。

## 完成标准

Phase 3 完成时，用户可以：

1. 在 Markdown 中定义多个 named `tasks` block。
2. 在任意位置执行 `:ObsidianTasks`。
3. 从 picker 选择 config query 或 block query。
4. 打开多个 pinned query result buffer。
5. 从结果 buffer 用 `gq` 跳回 query block。
6. 可选开启只读 inline preview。
