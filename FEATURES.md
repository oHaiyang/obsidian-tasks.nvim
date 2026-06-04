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
- 本插件第二阶段计划见 `PHASE_2.md`
- 本插件第三阶段计划见 `PHASE_3.md`

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
| 插件入口 | `setup(config)`，保存 `vault_path`、`display.hierarchical_headings`、`queries`、`default_query`。 |
| 查找任务 | `find_tasks(opts)` 支持 scanner 递归扫描 `.md` 文件；Phase 7.1 起可 opt-in 使用 vault task cache，并支持可配置 global filter 和 query text。 |
| 任务字段 | 解析 `status`、`text`、`file_path`、`line_number`、`heading`、priority、常用日期、tags、recurrence/id/dependsOn/onCompletion 等字段。 |
| 过滤 | 支持 include/exclude file pattern、status、custom Lua function，以及 query filters。 |
| 分组 | 支持 `status`、`priority`、`file/filename`、`heading`、常用 date fields，可用扁平标题或层级标题显示。 |
| 结果视图 | 普通 buffer 或 floating window，任务行带 `[[path#Lline]]` 元数据；支持 active/pinned Tasks panel。 |
| 编辑保存 | 可在结果 buffer 改状态并写回源文件；目前只替换 checkbox 状态。 |
| 快捷键 | `q` 关闭、`<c-s>` 保存、`<c-r>` 刷新、`<space>` toggle、`gd/gf` 跳源文件、`J/K` 跳任务、`o` query picker、`]q/[q` 切 query。 |
| 主要缺口 | 完整查询语言、循环任务、状态机、编辑 UI 还没有系统实现。 |

## 1. 任务识别与数据模型

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F001 | Markdown 任务识别 | 支持 `- [ ]`、`* [ ]`、`+ [ ]`、`1. [ ]`、`1) [ ]`，保留缩进和 list marker。 | Partial：已支持常见 marker，后续补更完整的 Obsidian metadata 行为。 | P0 |
| F002 | 只处理 Markdown 文件 | 原插件只读取 `.md` 文件。 | Partial：由传入 vault + rg 决定。 | P0 |
| F003 | 单行任务限制 | 原插件只解析单行 checklist item，多行正文不作为任务描述。 | Partial：当前逐行扫描天然单行。 | P0 |
| F004 | code block / comment 排除 | 原插件依赖 Obsidian metadata，不读取 code block 和注释中的任务。 | Partial：Phase 7.6 排除 fenced code、HTML comment 和 Obsidian `%%` comment 中的任务。 | P0 |
| F005 | blockquote / callout 中任务 | 支持 `>` 缩进中的任务，并记录其位置。 | Partial：Phase 7.6 支持 blockquote 任务扫描，并暴露 blockquote/callout metadata。 | P1 |
| F006 | 父子 list item / task 树 | 记录父级 ListItem，用于 `show tree`。 | Done：Phase 6.3 记录 list item parent/children，并支持 `show tree` 展示命中 task 的 child tree。 | P1 |
| F007 | 前置 heading | 记录任务前最近 heading，用于 backlink、filter/sort/group by heading。 | Done：scanner 记录最近 heading，并支持 filter/sort/group by heading。 | P0 |
| F008 | Global Filter | 可设置全局字符串，如 `#task`，只追踪包含该字符串的 checklist item。 | Done：支持 `global_filter` / `globalFilter`，Phase 7.6 对 tag 型 filter 使用 token 精确匹配。 | P0 |
| F009 | Remove global filter | 全局过滤 tag 可从描述和 `task.tags` 中移除。 | Done：Phase 7.6 支持 `remove_global_filter` / `removeGlobalFilter`。 | P1 |
| F010 | Tasks Emoji Format | 默认格式：优先级、日期、循环、on completion、依赖均用 emoji 字段。 | Partial：只解析优先级和 due。 | P0 |
| F011 | Dataview Format | 支持 `[due:: 2024-01-01]`、`[priority:: high]` 等 Dataview inline fields。 | Partial：Phase 6.7 支持 Dataview task format MVP 的解析、查询、主要编辑写回和补全入口。 | P2 |
| F012 | 描述字段 | 解析任务正文，metadata 从行尾剥离，保留用户可见描述。 | Partial。 | P0 |
| F013 | 解析顺序 | 从行尾向左解析 metadata；metadata 后只能继续放 tag/block link，否则左侧 metadata 不识别。 | Todo。 | P0 |
| F014 | Tags | 识别 task description 中 tag；支持较 Obsidian 更宽松的 tag 规则。 | Partial：已提取 description tags；Phase 7.6 会在 removeGlobalFilter 后再提取 tags。 | P0 |
| F015 | Block link | 支持行尾 `^block-id`，保存并写回。 | Partial：已解析 `^block-id`，并在 Phase 7.5 source location 中用于重定位；完整写回格式 parity 待补。 | P1 |
| F016 | Priority | 支持 `🔺` highest、`⏫` high、`🔼` medium、`🔽` low、`⏬` lowest、none。 | Partial：已解析并排序部分 priority。 | P0 |
| F017 | Date fields | 支持 created `➕`、start `🛫`、scheduled `⏳`、due `📅`、cancelled `❌`、done `✅`。 | Done：emoji format 常用日期已解析。 | P0 |
| F018 | Invalid date | 日期固定 `YYYY-MM-DD`；无效日期可被查询发现。 | Todo。 | P1 |
| F019 | Happens date | `happens` 为 start/scheduled/due 中最早的有效日期。 | Done：query/sort/group 可使用 happens。 | P1 |
| F020 | Created/done/cancelled 自动日期 | 新建或状态变化时按设置自动写入日期。 | Partial：done/cancelled 已支持；created 支持新 recurrence。 | P1 |
| F021 | Recurrence | 支持 `🔁 every ...`，基于 rrule 计算下一次任务。 | Partial：覆盖基础 every day/week/month/year；Phase 7.7 补常用 weekday/weekend、指定 weekday、`every N weeks on <weekday>` 和 monthday 规则。 | P1 |
| F022 | Recurrence `when done` | 可选择基于原日期或完成日期计算下一次。 | Partial：基础 `when done` 已支持。 | P1 |
| F023 | Recurrence 多日期联动 | due/scheduled/start 的相对偏移会随下一次任务一起平移。 | Partial：现按每个字段独立推进。 | P2 |
| F024 | Recurrence 插入位置 | 下一次任务可插入原任务上方或下方。 | Done。 | P2 |
| F025 | Recurrence 移除 scheduled | 设置开启时，下次循环可移除 scheduled date。 | Done。 | P2 |
| F026 | On Completion | 支持 `🏁 keep` 和 `🏁 delete`；完成时可删除已完成实例。 | Partial：recurrence 完成路径支持 `delete`。 | P2 |
| F027 | Dependencies | 支持 `🆔 id` 和 `⛔ dependsOn`，id 可跨 vault 被引用。 | Partial：已解析并用于 direct dependency 查询。 | P1 |
| F028 | Blocked / blocking | 基于未完成任务的 direct dependency 判断 `is blocked` / `is blocking`。 | Done。 | P1 |
| F029 | Custom statuses | 每个 status 有 symbol/name/next symbol/type/availableAsCommand。 | Done。 | P1 |
| F030 | Unknown status | 未配置的 status 默认为 name `Unknown`、type `TODO`、next `x`。 | Done。 | P1 |
| F031 | Status types | `TODO`、`IN_PROGRESS`、`ON_HOLD`、`DONE`、`CANCELLED`、`NON_TASK` 决定完成语义。 | Done：done/not done、toggle、dependencies 使用 status type。 | P1 |
| F032 | Urgency | 根据 due、priority、scheduled、start 计算数值分数。 | Done：Phase 6.2 支持原版 urgency score、`show urgency`、`sort/group by urgency` 和 `task.urgency`。 | P1 |
| F033 | File properties | 暴露 path/root/folder/filename/pathWithoutExtension 等。 | Partial：已暴露 task.file 的 path/folder/filename/pathWithoutExtension 等常用字段，root 暂未建模。 | P0 |
| F034 | Obsidian Properties | 读取 YAML/JSON frontmatter，供 custom query 使用。 | Partial：Phase 6.8 读取 Markdown YAML frontmatter，并暴露到 `task.frontmatter` / `task.properties` / `task.file.*` 和 `query.file.*`；Phase 8.2 支持普通 query 直接过滤 frontmatter/property 字段。JSON frontmatter 暂不支持。 | P2 |
| F035 | Links | 解析 task line、file body、frontmatter 中 outlinks。 | Partial：Phase 6.8 解析 task line 中的 wikilink 和 Markdown link，暴露为 `task.links` / `task.outlinks`；Phase 8.2 扫描 file-level outlinks 并支持普通 query 过滤 `links` / `outlinks` / `file.outlinks`。 | P3 |
| F036 | Filename as scheduled date | 从文件名推导 undated task 的 scheduled date。 | Todo。 | P2 |

## 2. Vault 扫描与缓存

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F101 | Vault-wide cache | 启动后索引全 vault markdown tasks，缓存为 Task 对象。 | Partial：Phase 7.1 提供 opt-in vault task cache API，并接入 finder/preview/dependency/completion；默认仍可走旧扫描路径。 | P0 |
| F102 | 增量更新 | 监听 create/delete/rename/change，更新单文件缓存。 | Partial：Phase 7.1 提供 `cache.update_file()` / `remove_file()` 手动 API；Phase 7.2 支持 `BufWritePost` 单文件自动更新；Phase 7.4 提供 opt-in vault watcher 处理外部 create/change/delete/rename 事件。 | P1 |
| F103 | Cold/Initializing/Warm 状态 | 查询渲染能感知 cache 状态。 | Partial：Phase 7.1 `cache.stats()` 暴露 cold/warm、file/task count；Phase 7.2 补 `last_update`。结果渲染暂不展示 cache 状态。 | P2 |
| F104 | Debounced redraw | 文件变化后 debounce 通知查询重绘。 | Partial：Phase 7.4 watcher 支持 debounced cache update；Phase 7.8 支持 opt-in debounced auto refresh 已打开 result buffers。 | P2 |
| F105 | 源文件定位 | 通过文件、line、section index 精准替换任务。 | Partial：Phase 7.5 支持 source signature，并在 result save/postpone/dependency/edit/jump 时按 line、id、block link、original markdown 重定位；复杂 diff/rename 仍待补。 | P0 |
| F106 | 重试与冲突处理 | Obsidian metadata 不稳定时会重试，避免写错行。 | Todo。 | P2 |
| F107 | 保留用户原格式 | 写回时保留缩进、list marker、status、metadata 排列。 | Partial：当前只替换 checkbox。 | P0 |
| F108 | 多文件修改 | 依赖编辑可一次修改多个文件。 | Todo。 | P2 |

## 3. Tasks 查询语言

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F201 | `tasks` code block | 在 Markdown 中写 ```tasks 查询并渲染结果。 | Partial：已可作为 named query definition 被发现和运行；未做 Obsidian-style 原地替换。 | P0 |
| F202 | 直接查询 API | 能把查询文本解析成 filters/sort/group/layout。 | Partial：已支持 Query Language MVP。 | P0 |
| F203 | Query 组合顺序 | Global Query -> Query File Defaults -> code block source。 | Done：Phase 5.3 已支持。 | P1 |
| F204 | `ignore global query` | 单个查询可跳过全局查询。 | Done：Phase 5.3 已支持 block query 和 `TQ_extra_instructions`。 | P1 |
| F205 | Comments | `# ...` 查询行作为注释忽略。 | Done：query parser 已忽略注释行。 | P0 |
| F206 | Line continuations | 反斜杠续行，便于长表达式。 | Todo。 | P2 |
| F207 | Limit | `limit <n>`、`limit groups <n>`。 | Partial：已支持 `limit <n>`。 | P0 |
| F208 | Explain | `explain` 显示查询如何被解析、日期如何展开、placeholder 如何替换。 | Todo。 | P2 |
| F209 | Presets | 设置中定义命名查询片段，用 `preset name` 或 `{{preset.name}}` 复用。 | Done：Phase 5 支持 `preset name`；Phase 5.2 支持单行 `{{preset.name}}`。 | P2 |
| F210 | Placeholders | `{{query.file.path}}` 等占位符按查询文件展开。 | Partial：Phase 5.2 支持 `query.file.*` 和 `preset.*`；其它 placeholder 待补。 | P2 |
| F211 | Query File Defaults | 文件 frontmatter 中 `TQ_*` 属性自动生成查询指令。 | Done：Phase 5.3 支持读取并注入；Phase 5.10 支持属性写入命令。 | P2 |
| F212 | Boolean filters | 支持 `(filter A) AND/OR/XOR/NOT (filter B)`，也支持 quoted delimiters。 | Done：Phase 5.1 支持括号 AND/OR/NOT；Phase 8.1 补 `XOR` 和 `[]` / `{}` / quote delimiters。 | P1 |
| F213 | Regex filters | `regex matches /.../i` 和 `regex does not match /.../i`。 | Partial：Phase 5 基于 `vim.regex()` 支持常用字段。 | P1 |
| F214 | Custom filters | `filter by function ...` 执行 JavaScript 表达式。 | Partial：Phase 5 支持 opt-in Lua 表达式。 | P2 |
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
| File | `path`、`root`、`folder`、`filename`、`heading`、`file.tags`、`file.aliases`、`file.outlinks` 的 include/regex 查询。 |
| Frontmatter / Links | `frontmatter.<key>`、`property.<key>`、`links`、`outlinks`、`file.outlinks` 的 include/regex 查询。 |
| Other via function | `originalMarkdown`、`lineNumber`、`listMarker` 等主要通过 custom function 查询。 |
| Sub-items | `exclude sub-items`。已支持 Phase 6.3 MVP。 |

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
| F302 | Backlink | 每条任务显示文件名和 heading，点击跳回源行。 | Partial：`gd/gf` 可跳转；Phase 5.4 支持 `show/hide backlink`。 | P0 |
| F303 | Edit button | 结果里有铅笔按钮打开编辑 modal。 | Todo。 | P2 |
| F304 | Postpone button | 结果里可一键或菜单推迟 due/scheduled/start。 | Partial：`p` / `:ObsidianTasksPostpone` 已支持基础推迟；Phase 6.5 date picker 对已有日期提供 advance/postpone 轻量菜单项。 | P1 |
| F305 | Toolbar | 查询结果顶部可临时过滤 description、复制结果为 Markdown。 | Done：Phase 6.4 支持 result buffer toolbar、临时 description filter 和 copy markdown。 | P2 |
| F306 | Task count | 显示命中数；limit 时显示 `shown of total`。 | Done：Phase 5.4 支持显示和 `show/hide task count`。 | P1 |
| F307 | Task count location | 全局设置 count 在 top 或 bottom。 | Todo。 | P3 |
| F308 | Hide/show task fields | `hide/show priority/due date/tags/...`。 | Partial：Phase 5.4 支持常用 task 字段。 | P1 |
| F309 | Hide/show query UI | `hide/show backlink/edit button/postpone button/toolbar/tree/urgency/task count`。 | Partial：Phase 5.4 支持 backlink/task count；Phase 6.2 支持 urgency；Phase 6.3 支持 tree；Phase 6.4 支持 toolbar；edit/postpone button 待补。 | P1 |
| F310 | Full mode | 默认展示字段值，如具体日期、循环规则。 | Partial：默认 full display，Phase 5.4 开始接 layout。 | P1 |
| F311 | Short mode | 只显示 emoji，具体值靠 tooltip。 | Partial：Phase 5.4 对 metadata 做轻量 short mode；tooltip 待补。 | P2 |
| F312 | Show tree | 展示匹配任务及其子任务/list item 树。 | Done：Phase 6.3 支持 `show tree` / `hide tree`。 | P1 |
| F313 | Styling hooks | HTML/CSS class 和 data attributes 支持自定义样式。 | Obsidian-only；nvim 可映射 highlights/extmarks。 | P3 |
| F314 | Error rendering | 查询错误、加载状态、explain 输出显示在结果中。 | Todo。 | P1 |
| F315 | Global Tasks panel | 在任意 buffer 打开任务面板，不需要先定位到 query block。 | Done：`:ObsidianTasks` 已支持。 | P0 |
| F316 | Query picker | 在任务面板中选择 config query、block query、recent query。 | Done：Phase 3 已支持三类 source。 | P0 |
| F317 | Pinned query results | 同时保留多个查询结果 buffer，例如 `:ObsidianTasks! due_soon`。 | Done：已支持 pinned result buffer。 | P1 |
| F318 | Query source jump | 从结果 buffer 跳回 query 定义来源。 | Done：block query 可用 `gq` 跳回 source line。 | P1 |
| F319 | Inline query preview | 用 virtual lines 在 `tasks` block 附近显示只读摘要。 | Partial：已支持只读 summary preview。 | P2 |

## 5. 编辑与命令

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F401 | Toggle task done | `Tasks: Toggle task done`，按 status registry 切换 next status。 | Done：Phase 4 已按 status registry 切换。 | P0 |
| F402 | 源文件 task toggle | 在普通 Markdown buffer 光标所在任务上切换并写回。 | Done：Phase 4 已支持 status-aware toggle。 | P0 |
| F403 | Done/cancelled date | 切换到 DONE/CANCELLED type 时自动添加日期，切出时移除。 | Done：`set_done_date` / `set_cancelled_date`。 | P1 |
| F404 | Recurring completion | 完成循环任务时创建下一次任务，并处理 done date、created date、依赖清空等。 | Partial：基础 recurrence 和 Phase 7.7 常用 weekday/monthday 规则已支持；复杂 natural-language recurrence 待补。 | P1 |
| F405 | Change status commands | 为每个 registered status 生成 `Change status to...` 命令。 | Done：`ObsidianTasksChangeStatus` 和 `ObsidianTasksStatus*`。 | P1 |
| F406 | Status context menu | 右键 checkbox 可选择任意 status。 | Obsidian-only；nvim 可做 picker。 | P2 |
| F407 | Create/Edit task modal | 新建或编辑任务字段：description、status、priority、recurrence、dates、dependencies。 | Partial：Phase 5 已支持 buffer form MVP；Phase 5.5 补日期解析和轻量 picker；Phase 5.6 补 auto-suggest MVP；Phase 5.7 抽 completion core；Phase 6.5 补 calendar date picker。 | P1 |
| F408 | Modal field visibility | 可隐藏不用字段。 | Todo。 | P3 |
| F409 | Date parsing in modal | 输入 `today`、`tomorrow`、`6 oct`、`2 weeks` 等自然语言日期。 | Done：Phase 5.5 支持常用自然日期并正规化保存。 | P1 |
| F410 | Date picker | 点击任务日期打开 date picker，能修改或清空日期。 | Partial：Phase 5.9 扩展 form `gd` 并提供普通 task 行 `ObsidianTasksPickDate`；Phase 6.5 支持 floating calendar picker、选择和清空日期。 | P2 |
| F411 | Date context menu | 右键日期可 advance/postpone。 | Partial：Phase 6.5 在 select picker 中提供已有日期的 `Advance 1 day` / `Postpone 1 day`，右键菜单本身不做。 | P2 |
| F412 | Postpone | 对 due/scheduled/start 选择第一个存在日期，推迟到 tomorrow 或更多日期。 | Partial：基础 `:ObsidianTasksPostpone` 已支持。 | P1 |
| F413 | Auto-suggest | 编辑任务时智能补 emoji、日期、recurrence、id/dependsOn、onCompletion。 | Partial：Phase 5.8 提供 completion core、form 补全、普通 Markdown task 行手动补全和可选 `nvim-cmp` source；Phase 6 Native Completion Adapter 支持原生补全、priority 前缀、due/scheduled 日期字段关键词和 Obsidian-style 常用日期语义；Phase 6.6 支持 dependency task search suggestions；Phase 6.7 支持 Dataview inline field completion MVP。 | P1 |
| F414 | Dependency editor | 在 modal 或 suggest 中搜索任务并自动生成 id/dependsOn。 | Partial：Phase 5.9 支持 form 和普通 task 行选择依赖，必要时自动补 `🆔 id`；Phase 6.6 与 completion 共用 task search 候选。 | P2 |
| F415 | Add Query File Defaults props | 命令把全部 `TQ_*` 属性写入当前 note frontmatter。 | Done：Phase 5.10 支持只补缺失属性并保留已有值。 | P3 |
| F416 | Save result edits | 查询结果中修改任务后写回源文件。 | Partial：已有 status 写回。 | P0 |
| F417 | Refresh result view | 重新运行上一次查询。 | Done：Phase 7.3 让 `<c-r>` / `:ObsidianTasksRefresh` 按当前 result buffer 自己的 finder opts 刷新，并支持 `:ObsidianTasksRefreshCache!`；Phase 7.8 支持 opt-in 自动刷新已打开 result buffers。 | P0 |

## 6. 设置项

| ID | 设置 | 原插件含义 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F501 | `globalFilter` | 只追踪包含指定字符串的 checklist item。 | Partial。 | P0 |
| F502 | `removeGlobalFilter` | 从描述和 tags 中隐藏/移除 global filter。 | Todo。 | P1 |
| F503 | `globalQuery` | 注入每个 tasks query 前面。 | Done：Phase 5.3 支持 `global_query` / `globalQuery`。 | P1 |
| F504 | `taskFormat` | `tasksPluginEmoji` 或 `dataview`。 | Partial：Phase 6.7 支持 `task_format` / `taskFormat = "dataview"` MVP；默认仍为 emoji format。 | P2 |
| F505 | `setCreatedDate` | 新建任务或新 recurrence 时添加 created date。 | Partial：new recurrence 可写 created date。 | P1 |
| F506 | `setDoneDate` | 完成任务时添加 done date。 | Done。 | P1 |
| F507 | `setCancelledDate` | 取消任务时添加 cancelled date。 | Done。 | P1 |
| F508 | `autoSuggestInEditor` | 是否启用 auto-suggest。 | Partial：Phase 5.6 支持 form buffer 内启用/关闭；Phase 5.8 支持可选 cmp source 注册；Phase 6 Native Completion Adapter 支持原生补全 opt-in。 | P2 |
| F509 | auto-suggest min/max | 控制建议触发长度和最多显示项。 | Partial：Phase 5.6 支持 `auto_suggest_min_chars` / `auto_suggest_max_items`。 | P2 |
| F510 | `useFilenameAsScheduledDate` | 从文件名推导 scheduled date。 | Todo。 | P2 |
| F511 | filename date format/folders | 自定义文件名日期格式和生效文件夹。 | Todo。 | P2 |
| F512 | recurrence settings | next recurrence 位置、是否移除 scheduled。 | Partial：已支持 `recurrence_on_next_line` 和 `remove_scheduled_date_on_recurrence`。 | P2 |
| F513 | `searchResults.taskCountLocation` | count 显示 top/bottom。 | Todo。 | P3 |
| F514 | `statusSettings` | 自定义 status registry。 | Done：支持 symbol/name/type/next_symbol。 | P1 |
| F515 | edit modal field visibility | 控制 modal 中显示哪些字段。 | Todo。 | P3 |
| F516 | debug/logging/options | 控制日志、调试行为、部分 feature flag。 | Todo。 | P3 |
| F517 | `queries` | 在 Neovim config 中定义 named queries。 | Done：Phase 2 已支持。 | P0 |
| F518 | `default_query` | `:ObsidianTasks` 不带参数时打开的默认 query。 | Done：Phase 2 已支持。 | P0 |

## 7. Scripting / API / 生态集成

| ID | 功能 | 原插件行为 | nvim 状态 | 优先级 |
| --- | --- | --- | --- | --- |
| F601 | Task properties | `task.*` 暴露 status、dates、dependencies、description、priority、file、frontmatter、links 等。 | Partial：已有基础字段、`task.file`、dependencies、Phase 6.2 `task.urgency`，Phase 6.8 补 `task.frontmatter` / `task.properties` / `task.links` / `task.outlinks`。 | P2 |
| F602 | Query properties | `query.file.*` 和 `query.allTasks`。 | Partial：Phase 5/5.2 提供 `query.allTasks`、`query.all_tasks`、`query.file`；Phase 6.8 补 query file frontmatter/tags/aliases/cssclasses。 | P2 |
| F603 | JavaScript expressions | custom filter/sort/group 运行 JS，需要显式启用。 | Obsidian-only；nvim 建议 Lua 表达式。 | P2 |
| F604 | TasksDate helper | 日期对象支持 `format()`、`category`、`fromNow` 等。 | Todo。 | P2 |
| F605 | API v1 | `createTaskLineModal()`、`editTaskLineModal()`、`executeToggleTaskDoneCommand()`。 | Todo；nvim 可提供 Lua API。 | P2 |
| F606 | Dataview interop | 可读写 Dataview inline field 格式。 | Partial：Phase 6.7 支持 task line inline fields，不读取 frontmatter Dataview 数据。 | P2 |
| F607 | QuickAdd / Kanban / Meta Bind docs | Obsidian 生态集成说明和部分适配。 | Obsidian-only。 | P3 |
| F608 | Reminder interop | 与 obsidian-reminder 约定 `⏰ YYYY-MM-DD HH:mm`。 | Todo；可作为兼容解析。 | P3 |
| F609 | i18n | 原插件带多语言 locale。 | Todo。 | P3 |

## 8. 当前阶段路线图

### Phase 1: Task Core MVP

状态：已手测通过，详见 `PHASE_1.md` 和 `PHASE_1_TEST.md`。

已覆盖：

1. Task parser / serializer。
2. configurable global filter。
3. Markdown scanner。
4. 查询结果 buffer toggle/save/jump/refresh。
5. 普通 Markdown buffer 当前行 toggle。

### Phase 2: Query Language + Tasks Panel MVP

状态：已实现第一版，详见 `PHASE_2.md` 和 `PHASE_2_TEST.md`。

目标是让用户在任意位置打开 Tasks panel，而不是必须先找到某个 `tasks` code block。

核心需求：

1. Query parser MVP：comments、limit、basic filters、date filters、sort、group。
2. Date helper：`YYYY-MM-DD`、`today/tomorrow/yesterday`、`happens`。
3. `find_tasks({ query = ... })`。
4. `setup({ queries = ..., default_query = ... })`。
5. `:ObsidianTasks` 全局面板。
6. `:ObsidianTasks! name` pinned 多查询结果。
7. Query picker：`o`、`]q`、`[q`。
8. Result buffer count、空结果、query error buffer。

### Phase 3: Named Query Blocks + Preview UX

状态：已实现第一版，详见 `PHASE_3.md` 和 `PHASE_3_TEST.md`。

目标是保留 Obsidian 的 `tasks` code block 心智，但让 Neovim 用户不需要手动定位 block 才能打开查询。

核心需求：

1. 扫描 vault 中的 named `tasks` code block。
2. 支持 `# name:` 和 `# id:` metadata。
3. Query registry 合并 config query、block query、recent query。
4. Picker 展示所有 query source。
5. `gq` 从结果 buffer 跳回 query block。
6. `:ObsidianTasksRefreshQueries`。
7. `run_query_at_cursor()` 和 `:ObsidianTasksRunBlock`。
8. 只读 inline preview MVP。

### Phase 4: Task Semantics

状态：已实现第一版，详见 `PHASE_4.md` 和 `PHASE_4_TEST.md`。

目标是补上会改变任务语义和源文件写回行为的能力。

核心需求：

1. Status registry：custom status、status type、next status。
2. Done/cancelled date 自动写回。
3. Recurring task 完成后生成下一次任务。
4. Dependencies：`is blocked` / `is blocking` query。
5. Postpone action。

### Phase 5: Editing and Advanced Query

状态：已实现第一版，Phase 5.1/5.2/5.3/5.4/5.5/5.6/5.7/5.8/5.9/5.10 已继续补 Boolean、placeholder、query composition、layout directives、edit form ergonomics、auto-suggest MVP、Markdown task line completion、可选 `nvim-cmp` source、dependency editor、better date picker 和 Query File Defaults 属性写入命令，详见 `PHASE_5.md`。

目标是接近 Obsidian Tasks 的高级使用体验。

当前核心需求：

1. Create/Edit task floating form。
2. Boolean / regex / function query MVP。
3. `preset name` 和单行 `{{preset.name}}` query expansion。
4. `{{query.file.*}}` placeholders。
5. Global Query、`ignore global query`、Query File Defaults。
6. Result view layout directives。
7. Edit form natural dates and lightweight pickers。
8. Edit form auto-suggest MVP。
9. Completion core 和普通 Markdown task 行手动补全。
10. 可选 `nvim-cmp` source。
11. Dependency editor 和 better date picker。
12. Query File Defaults 属性写入命令。

后续继续补：

1. XOR / bracket / quote Boolean delimiters。
2. 更完整的 Boolean parser delimiters、JSON frontmatter、file body/frontmatter outlinks。

### Phase 6: Polish and Ecosystem

状态：进行中，Phase 6.2 已实现 urgency，Phase 6.3 已实现 `show tree` / `exclude sub-items`，Phase 6.4 已实现 toolbar filter/copy，Phase 6.5 已实现 calendar date picker，Phase 6.6 已实现 task search suggestions，Phase 6.7 已实现 Dataview task format MVP，Phase 6.8 已实现 frontmatter/links scripting surface MVP，详见 `PHASE_6.md`。Phase 6 的目标是补齐原版 Obsidian Tasks 中对日常使用影响最大的 polish、diagnostics 和生态兼容能力。

建议拆分：

1. Phase 6.2：Urgency score、`show urgency`、`sort/group by urgency`。Done。
2. Phase 6 Native Completion Adapter：原生补全 adapter。Done。
3. Phase 6.3：`show tree`、父子 list item 与 sub-items。Done。
4. Phase 6.4：Toolbar filter/copy 和 result view polishing。Done。
5. Phase 6.5：Calendar-style date picker、date action menu、postpone/advance polish。Done。
6. Phase 6.6：Auto-suggest polish 和任务搜索建议。Done。
7. Phase 6.7：Dataview task format MVP。Done。
8. Phase 6.8：Frontmatter properties、links、scripting surface。Done。
9. Phase 6.1：Query diagnostics、`explain` 和错误渲染增强，暂缓。

### Phase 7: Cache, Incremental Updates, and Source Fidelity

状态：进行中，Phase 7.1 已实现 Vault Cache API MVP，Phase 7.2 已实现 `BufWritePost` 单文件 cache update，Phase 7.3 已实现 result refresh integration，Phase 7.4 已实现 file watcher + debounce，Phase 7.5 已实现 source location fidelity MVP，Phase 7.6 已实现 scanner parity cleanup，Phase 7.7 已实现 recurrence grammar expansion，Phase 7.8 已实现 auto refresh result buffers，详见 `PHASE_7.md`。

目标是让 nvim 插件从“每次查询全量扫描”推进到 cache-first 的底层模型，同时为后续自动刷新和更可靠写回做准备。

建议拆分：

1. Phase 7.1：Vault Cache API MVP。Done，详见 `PHASE_7_1.md`。
2. Phase 7.2：`BufWritePost` 单文件 cache update。Done，详见 `PHASE_7_2.md`。
3. Phase 7.3：Result refresh integration。Done，详见 `PHASE_7_3.md`。
4. Phase 7.4：File watcher + debounce。Done，详见 `PHASE_7_4.md`。
5. Phase 7.5：Source location fidelity，减少旧 result buffer 写错行风险。Done，详见 `PHASE_7_5.md`。
6. Phase 7.6：Scanner parity cleanup。Done，详见 `PHASE_7_6.md`。
7. Phase 7.7：Recurrence grammar expansion。Done，详见 `PHASE_7_7.md`。
8. Phase 7.8：Auto refresh result buffers。Done，详见 `PHASE_7_8.md`。

### Phase 8: Query Parity and Diagnostics

状态：进行中，Phase 8.1 已实现 Boolean parser hardening，Phase 8.2 已实现 file/frontmatter/link query surface，详见 `PHASE_8.md`。

建议拆分：

1. Phase 8.1：Boolean parser hardening。Done，详见 `PHASE_8_1.md`。
2. Phase 8.2：File/frontmatter/link query surface。Done，详见 `PHASE_8_2.md`。
3. Phase 8.3：Query diagnostics and explain。
