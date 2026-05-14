# Obsidian Tasks 功能清单

这份清单用于后续补完 `obsidian-tasks.nvim`。它按用户可感知功能梳理原版 Obsidian Tasks 插件，而不是按源码目录机械拆分。

来源主要来自：

- `../obsidian-tasks/README.md`
- `../obsidian-tasks/docs/Getting Started`
- `../obsidian-tasks/docs/Queries`
- `../obsidian-tasks/docs/Editing`
- `../obsidian-tasks/docs/Scripting`
- `../obsidian-tasks/docs/Advanced`
- `../obsidian-tasks/src/Task`
- `../obsidian-tasks/src/Query`
- `../obsidian-tasks/src/Renderer`
- `../obsidian-tasks/src/Commands`
- 本插件第一阶段计划见 `PHASE_1.md`

## 图例

- `Done`: 当前 nvim 版本已有可用雏形。
- `Partial`: 当前 nvim 版本有一点覆盖，但和原插件差距明显。
- `Todo`: 当前 nvim 版本基本未覆盖。
- `Obsidian-only`: 强依赖 Obsidian UI/API，nvim 里可以做等价能力，但不必 1:1。
- `P0`: 最小可用核心。
- `P1`: 接近原插件日常体验。
- `P2`: 高级能力。
- `P3`: 生态集成或锦上添花。

## 当前 nvim 插件基线

| 能力 | 当前状态 |
| --- | --- |
| 插件入口 | `setup(config)`，保存 `vault_path` 和 `display.hierarchical_headings`。 |
| 查找任务 | `find_tasks(opts)` 通过 scanner 递归扫描 `.md` 文件，并支持可配置 global filter。 |
| 任务字段 | 解析 `status`、`text`、`file_path`、`line_number`、`heading`、priority、常用日期、tags、recurrence/id/dependsOn/onCompletion 等字段。 |
| 过滤 | 支持 include/exclude file pattern、status、custom Lua function。 |
| 分组 | 支持 `status`、`priority`、`file`，可用扁平标题或层级标题显示。 |
| 结果视图 | 普通 buffer 或 floating window，任务行带 `[[path#Lline]]` 元数据。 |
| 编辑保存 | 可在结果 buffer 改状态并写回源文件；目前只替换 checkbox 状态。 |
| 快捷键 | `q` 关闭、`<c-s>` 保存、`<c-r>` 刷新、`<space>` toggle、`gd/gf` 跳源文件、`J/K` 跳任务。 |
| 主要缺口 | 完整查询语言、日期行为、循环任务、状态机、代码块渲染、编辑 UI 都还没有系统实现。 |

## 1. 任务识别与数据模型

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F001 | Markdown 任务识别 | 支持 `- [ ]`、`* [ ]`、`+ [ ]`、`1. [ ]`、`1) [ ]`，保留缩进和 list marker。 | Partial：已支持常见 marker，后续补更完整的 Obsidian metadata 行为。 | P0 |
| F002 | 只处理 Markdown 文件 | 原插件只读取 `.md` 文件。 | Partial：由传入 vault + rg 决定。 | P0 |
| F003 | 单行任务限制 | 原插件只解析单行 checklist item，多行正文不作为任务描述。 | Partial：当前逐行扫描天然单行。 | P0 |
| F004 | code block / comment 排除 | 原插件依赖 Obsidian metadata，不读取 code block 和注释中的任务。 | Todo。 | P0 |
| F005 | blockquote / callout 中任务 | 支持 `>` 缩进中的任务，并记录其位置。 | Todo。 | P1 |
| F006 | 父子 list item / task 树 | 记录父级 ListItem，用于 `show tree`。 | Todo。 | P1 |
| F007 | 前置 heading | 记录任务前最近 heading，用于 backlink、filter/sort/group by heading。 | Todo。 | P0 |
| F008 | Global Filter | 可设置全局字符串，如 `#task`，只追踪包含该字符串的 checklist item。 | Partial：已支持配置，后续补 removeGlobalFilter 等细节。 | P0 |
| F009 | Remove global filter | 全局过滤 tag 可从描述和 `task.tags` 中移除。 | Todo。 | P1 |
| F010 | Tasks Emoji Format | 默认格式：优先级、日期、循环、on completion、依赖均用 emoji 字段。 | Partial：只解析优先级和 due。 | P0 |
| F011 | Dataview Format | 支持 `[due:: 2024-01-01]`、`[priority:: high]` 等 Dataview inline fields。 | Todo。 | P2 |
| F012 | 描述字段 | 解析任务正文，metadata 从行尾剥离，保留用户可见描述。 | Partial。 | P0 |
| F013 | 解析顺序 | 从行尾向左解析 metadata；metadata 后只能继续放 tag/block link，否则左侧 metadata 不识别。 | Todo。 | P0 |
| F014 | Tags | 识别 task description 中 tag；支持较 Obsidian 更宽松的 tag 规则。 | Todo。 | P0 |
| F015 | Block link | 支持行尾 `^block-id`，保存并写回。 | Todo。 | P1 |
| F016 | Priority | 支持 `🔺` highest、`⏫` high、`🔼` medium、`🔽` low、`⏬` lowest、none。 | Partial：已解析并排序部分 priority。 | P0 |
| F017 | Date fields | 支持 created `➕`、start `🛫`、scheduled `⏳`、due `📅`、cancelled `❌`、done `✅`。 | Partial：只解析 due。 | P0 |
| F018 | Invalid date | 日期固定 `YYYY-MM-DD`；无效日期可被查询发现。 | Todo。 | P1 |
| F019 | Happens date | `happens` 为 start/scheduled/due 中最早的有效日期。 | Todo。 | P1 |
| F020 | Created/done/cancelled 自动日期 | 新建或状态变化时按设置自动写入日期。 | Todo。 | P1 |
| F021 | Recurrence | 支持 `🔁 every ...`，基于 rrule 计算下一次任务。 | Todo。 | P1 |
| F022 | Recurrence `when done` | 可选择基于原日期或完成日期计算下一次。 | Todo。 | P1 |
| F023 | Recurrence 多日期联动 | due/scheduled/start 的相对偏移会随下一次任务一起平移。 | Todo。 | P2 |
| F024 | Recurrence 插入位置 | 下一次任务可插入原任务上方或下方。 | Todo。 | P2 |
| F025 | Recurrence 移除 scheduled | 设置开启时，下次循环可移除 scheduled date。 | Todo。 | P2 |
| F026 | On Completion | 支持 `🏁 keep` 和 `🏁 delete`；完成时可删除已完成实例。 | Todo。 | P2 |
| F027 | Dependencies | 支持 `🆔 id` 和 `⛔ dependsOn`，id 可跨 vault 被引用。 | Todo。 | P1 |
| F028 | Blocked / blocking | 基于未完成任务的 direct dependency 判断 `is blocked` / `is blocking`。 | Todo。 | P1 |
| F029 | Custom statuses | 每个 status 有 symbol/name/next symbol/type/availableAsCommand。 | Todo。 | P1 |
| F030 | Unknown status | 未配置的 status 默认为 name `Unknown`、type `TODO`、next `x`。 | Partial：当前只保留 symbol。 | P1 |
| F031 | Status types | `TODO`、`IN_PROGRESS`、`ON_HOLD`、`DONE`、`CANCELLED`、`NON_TASK` 决定完成语义。 | Todo。 | P1 |
| F032 | Urgency | 根据 due、priority、scheduled、start 计算数值分数。 | Todo。 | P1 |
| F033 | File properties | 暴露 path/root/folder/filename/pathWithoutExtension 等。 | Partial：当前只有 file_path。 | P0 |
| F034 | Obsidian Properties | 读取 YAML/JSON frontmatter，供 custom query 使用。 | Todo。 | P2 |
| F035 | Links | 解析 task line、file body、frontmatter 中 outlinks。 | Todo。 | P3 |
| F036 | Filename as scheduled date | 从文件名推导 undated task 的 scheduled date。 | Todo。 | P2 |

## 2. Vault 扫描与缓存

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F101 | Vault-wide cache | 启动后索引全 vault markdown tasks，缓存为 Task 对象。 | Partial：每次 find 用 rg。 | P0 |
| F102 | 增量更新 | 监听 create/delete/rename/change，更新单文件缓存。 | Todo。 | P1 |
| F103 | Cold/Initializing/Warm 状态 | 查询渲染能感知 cache 状态。 | Todo。 | P2 |
| F104 | Debounced redraw | 文件变化后 debounce 通知查询重绘。 | Todo。 | P2 |
| F105 | 源文件定位 | 通过文件、line、section index 精准替换任务。 | Partial：按 line_number 写回。 | P0 |
| F106 | 重试与冲突处理 | Obsidian metadata 不稳定时会重试，避免写错行。 | Todo。 | P2 |
| F107 | 保留用户原格式 | 写回时保留缩进、list marker、status、metadata 排列。 | Partial：当前只替换 checkbox。 | P0 |
| F108 | 多文件修改 | 依赖编辑可一次修改多个文件。 | Todo。 | P2 |

## 3. Tasks 查询语言

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F201 | `tasks` code block | 在 Markdown 中写 ```tasks 查询并渲染结果。 | Todo。 | P0 |
| F202 | 直接查询 API | 能把查询文本解析成 filters/sort/group/layout。 | Todo。 | P0 |
| F203 | Query 组合顺序 | Global Query -> Query File Defaults -> code block source。 | Todo。 | P1 |
| F204 | `ignore global query` | 单个查询可跳过全局查询。 | Todo。 | P1 |
| F205 | Comments | `# ...` 查询行作为注释忽略。 | Todo。 | P0 |
| F206 | Line continuations | 反斜杠续行，便于长表达式。 | Todo。 | P2 |
| F207 | Limit | `limit <n>`、`limit groups <n>`。 | Todo。 | P0 |
| F208 | Explain | `explain` 显示查询如何被解析、日期如何展开、placeholder 如何替换。 | Todo。 | P2 |
| F209 | Presets | 设置中定义命名查询片段，用 `preset name` 或 `{{preset.name}}` 复用。 | Todo。 | P2 |
| F210 | Placeholders | `{{query.file.path}}` 等占位符按查询文件展开。 | Todo。 | P2 |
| F211 | Query File Defaults | 文件 frontmatter 中 `TQ_*` 属性自动生成查询指令。 | Todo。 | P2 |
| F212 | Boolean filters | 支持 `(filter A) AND/OR/XOR/NOT (filter B)`，也支持 quoted delimiters。 | Todo。 | P1 |
| F213 | Regex filters | `regex matches /.../i` 和 `regex does not match /.../i`。 | Todo。 | P1 |
| F214 | Custom filters | `filter by function ...` 执行 JavaScript 表达式。 | Todo；nvim 可考虑 Lua 表达式。 | P2 |
| F215 | Custom sorting | `sort by function ...`。 | Todo；nvim 可考虑 Lua 表达式。 | P2 |
| F216 | Custom grouping | `group by function ...`。 | Todo；nvim 可考虑 Lua 表达式。 | P2 |

### 3.1 内置 filters

| 领域 | 原插件查询能力 |
| --- | --- |
| Status | `done`、`not done`、`status.name includes/does not include/regex...`、`status.type is/is not ...`。 |
| Dependencies | `is blocked`、`is not blocked`、`is blocking`、`is not blocking`、`has id`、`no id`、`id includes/regex...`、`has depends on`、`no depends on`。 |
| Dates | 对 `due`、`done`、`scheduled`、`starts`、`created`、`cancelled`、`happens` 支持 `on`、`before`、`after`、`on or before`、`on or after`、`in` 等。 |
| Date existence | `has due date`、`no due date`、`due date is invalid` 等日期存在性和无效值查询。 |
| Date ranges | 支持 absolute date、relative date、`last/this/next week/month/quarter/year`、`YYYY-Www`、`YYYY-MM`、`YYYY-Qq`、`YYYY` 等范围。 |
| Description | `description includes/does not include/regex...`。 |
| Priority | `priority is/above/below/not lowest|low|none|medium|high|highest`。 |
| Recurrence | `is recurring`、`is not recurring`、`recurrence includes/regex...`。 |
| Tags | `has tags`、`no tags`、`tag/tags include/do not include/regex...`。 |
| File | `path`、`root`、`folder`、`filename`、`heading` 的 include/regex 查询。 |
| Other via function | `originalMarkdown`、`lineNumber`、`listMarker`、frontmatter、links 等主要通过 custom function 查询。 |
| Sub-items | `exclude sub-items`。 |

### 3.2 内置 sorting

| 领域 | 原插件排序能力 |
| --- | --- |
| 默认排序 | 自动追加 `sort by status.type`、`sort by urgency`、`sort by due`、`sort by priority`、`sort by path`。 |
| Status | `sort by status`、`status.name`、`status.type`。 |
| Dependencies | `sort by id`。 |
| Dates | `sort by done/due/scheduled/start/created/cancelled/happens`。 |
| Task fields | `sort by description`、`priority`、`urgency`、`recurring`、`tag`、`tag <n>`、`random`。 |
| File fields | `sort by path/root/folder/filename/heading`。 |
| Reverse | 大多数排序支持 `reverse`。 |
| Multiple sorts | 多条 `sort by ...` 按顺序组合。 |

### 3.3 内置 grouping

| 领域 | 原插件分组能力 |
| --- | --- |
| Status | `group by status`、`status.name`、`status.type`。 |
| Dependencies | `group by id`、`depends on`。 |
| Dates | `group by done/due/scheduled/start/created/cancelled/happens`，按日期或无日期分组。 |
| Task fields | `group by priority`、`urgency`、`recurring`、`recurrence`、`tags`、`description`、`description without tags`。 |
| File fields | `group by path/root/folder/filename/backlink/heading`。 |
| Multiple groups | 多条 `group by ...` 形成多级分组。 |
| Refinement | 支持 `reverse` 和 group size limit。 |
| Custom groups | `group by function` 可返回字符串或字符串数组。 |

## 4. 查询结果渲染与交互

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F301 | 查询结果列表 | 在 Reading/Live Preview 中渲染 tasks block。 | Partial：有独立结果 buffer。 | P0 |
| F302 | Backlink | 每条任务显示文件名和 heading，点击跳回源行。 | Partial：`gd/gf` 根据 `[[path#Lline]]` 跳转。 | P0 |
| F303 | Edit button | 结果里有铅笔按钮打开编辑 modal。 | Todo。 | P2 |
| F304 | Postpone button | 结果里可一键或菜单推迟 due/scheduled/start。 | Todo。 | P1 |
| F305 | Toolbar | 查询结果顶部可临时过滤 description、复制结果为 Markdown。 | Todo。 | P2 |
| F306 | Task count | 显示命中数；limit 时显示 `shown of total`。 | Todo。 | P1 |
| F307 | Task count location | 全局设置 count 在 top 或 bottom。 | Todo。 | P3 |
| F308 | Hide/show task fields | `hide/show priority/due date/tags/...`。 | Todo。 | P1 |
| F309 | Hide/show query UI | `hide/show backlink/edit button/postpone button/toolbar/tree/urgency/task count`。 | Todo。 | P1 |
| F310 | Full mode | 默认展示字段值，如具体日期、循环规则。 | Partial。 | P1 |
| F311 | Short mode | 只显示 emoji，具体值靠 tooltip。 | Todo；nvim 可用 virtual text/float。 | P2 |
| F312 | Show tree | 展示匹配任务及其子任务/list item 树。 | Todo。 | P1 |
| F313 | Styling hooks | HTML/CSS class 和 data attributes 支持自定义样式。 | Obsidian-only；nvim 可映射 highlights/extmarks。 | P3 |
| F314 | Error rendering | 查询错误、加载状态、explain 输出显示在结果中。 | Todo。 | P1 |

## 5. 编辑与命令

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F401 | Toggle task done | `Tasks: Toggle task done`，按 status registry 切换 next status。 | Partial：只在结果 buffer `[ ]`/`[x]` 切换。 | P0 |
| F402 | 源文件 task toggle | 在普通 Markdown buffer 光标所在任务上切换并写回。 | Done：已支持当前行 `[ ]`/`[x]` 简单切换。 | P0 |
| F403 | Done/cancelled date | 切换到 DONE/CANCELLED type 时自动添加日期，切出时移除。 | Todo。 | P1 |
| F404 | Recurring completion | 完成循环任务时创建下一次任务，并处理 done date、created date、依赖清空等。 | Todo。 | P1 |
| F405 | Change status commands | 为每个 registered status 生成 `Change status to...` 命令。 | Todo。 | P1 |
| F406 | Status context menu | 右键 checkbox 可选择任意 status。 | Obsidian-only；nvim 可做 picker。 | P2 |
| F407 | Create/Edit task modal | 新建或编辑任务字段：description、status、priority、recurrence、dates、dependencies。 | Todo；nvim 可做 float form。 | P1 |
| F408 | Modal field visibility | 可隐藏不用字段。 | Todo。 | P3 |
| F409 | Date parsing in modal | 输入 `today`、`tomorrow`、`6 oct`、`2 weeks` 等自然语言日期。 | Todo。 | P1 |
| F410 | Date picker | 点击任务日期打开 date picker，能修改或清空日期。 | Obsidian-only；nvim 可做 calendar/picker。 | P2 |
| F411 | Date context menu | 右键日期可 advance/postpone。 | Obsidian-only；nvim 可做 action menu。 | P2 |
| F412 | Postpone | 对 due/scheduled/start 选择第一个存在日期，推迟到 tomorrow 或更多日期。 | Todo。 | P1 |
| F413 | Auto-suggest | 编辑任务时智能补 emoji、日期、recurrence、id/dependsOn、onCompletion。 | Todo。 | P1 |
| F414 | Dependency editor | 在 modal 或 suggest 中搜索任务并自动生成 id/dependsOn。 | Todo。 | P2 |
| F415 | Add Query File Defaults props | 命令把全部 `TQ_*` 属性写入当前 note frontmatter。 | Todo。 | P3 |
| F416 | Save result edits | 查询结果中修改任务后写回源文件。 | Partial：已有 status 写回。 | P0 |
| F417 | Refresh result view | 重新运行上一次查询。 | Done：已有 `<c-r>` 雏形。 | P0 |

## 6. 设置项

| ID | 设置 | 原插件含义 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F501 | `globalFilter` | 只追踪包含指定字符串的 checklist item。 | Partial。 | P0 |
| F502 | `removeGlobalFilter` | 从描述和 tags 中隐藏/移除 global filter。 | Todo。 | P1 |
| F503 | `globalQuery` | 注入每个 tasks query 前面。 | Todo。 | P1 |
| F504 | `taskFormat` | `tasksPluginEmoji` 或 `dataview`。 | Todo。 | P2 |
| F505 | `setCreatedDate` | 新建任务或新 recurrence 时添加 created date。 | Todo。 | P1 |
| F506 | `setDoneDate` | 完成任务时添加 done date。 | Todo。 | P1 |
| F507 | `setCancelledDate` | 取消任务时添加 cancelled date。 | Todo。 | P1 |
| F508 | `autoSuggestInEditor` | 是否启用 auto-suggest。 | Todo。 | P2 |
| F509 | auto-suggest min/max | 控制建议触发长度和最多显示项。 | Todo。 | P2 |
| F510 | `useFilenameAsScheduledDate` | 从文件名推导 scheduled date。 | Todo。 | P2 |
| F511 | filename date format/folders | 自定义文件名日期格式和生效文件夹。 | Todo。 | P2 |
| F512 | recurrence settings | next recurrence 位置、是否移除 scheduled。 | Todo。 | P2 |
| F513 | `searchResults.taskCountLocation` | count 显示 top/bottom。 | Todo。 | P3 |
| F514 | `statusSettings` | 自定义 status registry。 | Todo。 | P1 |
| F515 | edit modal field visibility | 控制 modal 中显示哪些字段。 | Todo。 | P3 |
| F516 | debug/logging/options | 控制日志、调试行为、部分 feature flag。 | Todo。 | P3 |

## 7. Scripting / API / 生态集成

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F601 | Task properties | `task.*` 暴露 status、dates、dependencies、description、priority、file、frontmatter、links 等。 | Todo。 | P2 |
| F602 | Query properties | `query.file.*` 和 `query.allTasks`。 | Todo。 | P2 |
| F603 | JavaScript expressions | custom filter/sort/group 运行 JS，需要显式启用。 | Obsidian-only；nvim 建议 Lua 表达式。 | P2 |
| F604 | TasksDate helper | 日期对象支持 `format()`、`category`、`fromNow` 等。 | Todo。 | P2 |
| F605 | API v1 | `createTaskLineModal()`、`editTaskLineModal()`、`executeToggleTaskDoneCommand()`。 | Todo；nvim 可提供 Lua API。 | P2 |
| F606 | Dataview interop | 可读写 Dataview inline field 格式。 | Todo。 | P2 |
| F607 | QuickAdd / Kanban / Meta Bind docs | Obsidian 生态集成说明和部分适配。 | Obsidian-only。 | P3 |
| F608 | Reminder interop | 与 obsidian-reminder 约定 `⏰ YYYY-MM-DD HH:mm`。 | Todo；可作为兼容解析。 | P3 |
| F609 | i18n | 原插件带多语言 locale。 | Todo。 | P3 |

## 8. 建议的 nvim 实现切片

### P0: 可用核心

1. 建立完整 Task parser/serializer：list marker、status、description、priority、dates、tags、block link、file location。
2. 去掉硬编码 `#t`，实现 configurable global filter。
3. 做 query parser 的第一层：comments、limit、basic filters、sort、group。
4. 支持 `tasks` code block 或至少 `:ObsidianTasksQuery` 直接执行查询文本。
5. 加强写回：保留原缩进/list marker，只改目标字段。
6. 支持在源 Markdown buffer 直接 toggle 当前任务。

### P1: 日常体验接近 Obsidian Tasks

1. Date filters/sorting/grouping：due/start/scheduled/done/created/cancelled/happens。
2. Status registry：custom status、status types、next status。
3. 完成任务时处理 done/cancelled date 和 recurring task。
4. 查询结果 layout：hide/show、task count、backlink、show tree。
5. Auto-suggest MVP：priority、date emoji、common dates、recurrence snippets。
6. Postpone action。

### P2: 高级能力

1. Dependencies：id/dependsOn、blocked/blocking、dependency picker。
2. Presets、placeholders、query file defaults。
3. Dataview task format。
4. Lua custom filter/sort/group，替代原插件 JS scripting。
5. Frontmatter properties 和 link properties。
6. Create/Edit task floating form。

### P3: 生态和抛光

1. 高级 UI：date picker、status picker、toolbar filter/copy。
2. Highlight/extmark 样式系统。
3. Reminder 兼容字段。
4. i18n、debug logging、文档和 demo vault。
