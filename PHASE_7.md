# Phase 7: Cache, Incremental Updates, and Source Fidelity

目标：把 `obsidian-tasks.nvim` 从“每次查询全量扫描 vault”的模型，推进到更接近原版 Obsidian Tasks 的 cache-first 模型，并为后续更可靠的写回、刷新、watcher 和大 vault 性能打地基。

Phase 6 已补齐大量日常交互和原版 parity 能力。Phase 7 不再优先补小 UI polish，而是处理会影响长期可用性的底层问题：

- 大 vault 查询性能。
- 查询结果、preview、dependency search、completion 共享同一份任务索引。
- 文件保存后只更新单文件 cache。
- 后续支持自动刷新 active/pinned result buffers。
- 写回源文件时减少 line number drift 风险。

Phase 6.1 Query diagnostics / explain 仍按用户决策暂缓。

## 原版依据

原版 Obsidian Tasks 借助 Obsidian metadata/cache 体系维护任务索引，查询时从 cache 读取 Task 对象，而不是每次临时扫描所有 Markdown 文件。nvim 版本不能直接复用 Obsidian metadata，但可以实现等价的 vault task cache：

- 冷启动：按 vault 扫描 Markdown 文件。
- Warm cache：查询直接读取任务数组。
- 单文件更新：保存或显式命令后只重扫该文件。
- 删除/重命名：移除或迁移对应 file entry。
- 结果刷新：cache 更新后让查询结果可手动或自动刷新。

## Phase 7 拆分

### Phase 7.1: Vault Cache API MVP

状态：Done，详见 `PHASE_7_1.md` 和 `PHASE_7_1_TEST.md`。

目标：

1. 新增 `lua/obsidian-tasks/cache.lua`。
2. 提供可控启用的 cache：
   - 默认不强制改变旧行为。
   - `setup({ cache = { enabled = true } })` 或 `setup({ cache_enabled = true })` 启用。
   - 单次调用可用 `use_cache` / `useCache` 覆盖。
3. API：
   - `cache.refresh(opts)`：扫描 vault 并 warm cache。
   - `cache.tasks(opts)`：启用 cache 时返回缓存任务列表，否则走原 scanner。
   - `cache.update_file(path, opts)`：重扫单个 Markdown 文件。
   - `cache.remove_file(path)`：从 cache 移除文件。
   - `cache.clear()`：清空 cache。
   - `cache.stats()`：返回 status、file_count、task_count、context。
4. 接入调用方：
   - `finder.find_tasks()`。
   - inline preview。
   - dependency/task search。
   - completion existing ids。
5. 用户命令：
   - `:ObsidianTasksRefreshCache`
   - `:ObsidianTasksClearCache`
   - `:ObsidianTasksCacheInfo`

边界：

- 本阶段不自动监听文件变化。
- 本阶段不自动刷新已打开 result buffer。
- cache context 先按 `vault_path`、`global_filter`、`today`、`task_format` 区分。
- 返回给调用方的是 task array 的浅拷贝，避免排序等路径改动 cache 数组本身。

### Phase 7.2: BufWritePost Single-file Cache Update

状态：Done，详见 `PHASE_7_2.md` 和 `PHASE_7_2_TEST.md`。

目标：

1. cache enabled 时注册 augroup。
2. `BufWritePost *.md` 且文件位于 vault 下时：
   - 调用 `cache.update_file(path)`。
   - 可选 debounce，避免保存风暴。
3. 普通 task mutation 写回后，如果没有触发 BufWritePost，也应显式 update cache。
4. 对删除/重命名暂不做 watcher，只提供显式 refresh/clear。

验收：

- 打开 query result 后修改源文件并保存，再刷新 result buffer 能看到新任务。
- dependency search / completion id list 在保存后能看到新 id。
- cache disabled 时行为保持旧逻辑。

### Phase 7.3: Result Refresh Integration

状态：Done，详见 `PHASE_7_3.md` 和 `PHASE_7_3_TEST.md`。

目标：

1. `display.refresh_tasks_view()` 保留当前 query/source/layout 并走 cache。
2. cache 更新后可选择刷新当前 active result buffer。
3. `cache.stats()` 可辅助显示 cache warm/cold 状态。
4. 后续若需要，result buffer 顶部显示 cache status。

验收：

- `<C-r>` 刷新 active/pinned buffer 时不全量扫描。
- active/pinned buffers 不互相污染 finder opts。

### Phase 7.4: File Watcher + Debounce

目标：

1. 用 libuv fs_event 或 Neovim autocmd 方案监听 vault 内 Markdown 文件变化。
2. 支持 create/delete/change。
3. debounce 后批量 update/remove。
4. 遇到 watcher 不可用时退回手动 refresh，不影响查询。

边界：

- 跨平台 watcher 差异大，先做可关闭。
- 大 vault 下 watch root 还是 watch files 需要测试后决定。

### Phase 7.5: Source Location Fidelity

状态：Done，详见 `PHASE_7_5.md` 和 `PHASE_7_5_TEST.md`。

目标：

1. 减少 `line_number` 过期时写错行风险。
2. task model 保留 source signature：
   - `original_markdown`
   - file path
   - line number
   - optional block link
   - nearby heading/list context
3. 写回时先校验 line number 仍匹配原任务。
4. 不匹配时在附近窗口搜索同一 `original_markdown` 或 `id`。
5. 仍无法定位时拒绝写回并提示用户刷新。

验收：

- 在源文件插入行后，旧 result buffer toggle 不应写错其它任务。
- 有 `🆔 id` 的任务可在 line drift 后重新定位。

### Phase 7.6: Scanner Parity Cleanup

目标：

1. 明确 code fence、HTML comment、Obsidian comment 中任务是否被扫描。
2. 支持 blockquote/callout 中任务的 source metadata。
3. 完成 heading 记录状态更新。
4. 补 `removeGlobalFilter`。
5. 补 filename-as-scheduled-date 的配置入口。

验收：

- scanner behavior 和 `FEATURES.md` 状态一致。
- 不破坏现有 show tree / sub-items。

### Phase 7.7: Recurrence Grammar Expansion

目标：

1. 扩展 `every ...` grammar。
2. 更接近原版 `when done`、`every!`、weekday/monthday 语义。
3. 多日期联动策略明确化。

边界：

- 这块规则复杂，建议在 cache/source fidelity 稳定后做。

## 当前推荐顺序

1. Phase 7.1 已完成。
2. Phase 7.2 已完成。
3. Phase 7.3 已完成。
4. Phase 7.5 已完成。
5. 下一步建议做 Phase 7.6 Scanner Parity Cleanup，补齐 scanner 层与 `FEATURES.md` 的明显状态差异。
6. Phase 7.4 watcher 和 Phase 7.7 recurrence grammar 能力根据实际使用痛点排序。
