# Phase 8: Query Parity and Diagnostics

目标：在 Phase 7 的 cache/source 基础稳定后，继续追 Obsidian Tasks 查询语言的可用性和可诊断性。Phase 8 优先处理复杂 query 的 parser、file/frontmatter/link 查询 surface，以及 `explain`/错误渲染。

## Phase 8.1: Boolean Parser Hardening

状态：Done，详见 `PHASE_8_1.md` 和 `PHASE_8_1_TEST.md`。

目标：

1. 支持 `XOR`。
2. Boolean operand 支持多种 delimiter：
   - `(filter)`
   - `[filter]`
   - `{filter}`
   - `"filter"`
   - `'filter'`
3. 保持裸 `A AND B` 不自动解析为 Boolean，避免和普通 instruction 文本冲突。
4. 对未匹配 delimiter 给出 query parse error。

## Phase 8.2: File, Frontmatter, and Link Query Surface

状态：Done，详见 `PHASE_8_2.md` 和 `PHASE_8_2_TEST.md`。

目标：

1. 增强 `field_text()`，支持 `file.*` / `frontmatter.*` / `properties.*` / `links` / `outlinks`。
2. 支持常用 include/regex 查询：
   - `frontmatter.<key> includes <value>`
   - `property.<key> includes <value>`
   - `file.tags includes <tag>`
   - `links include <target>`
   - `outlinks include <target>`
3. 尽量复用 Phase 6.8 已有 task/file fields，不另起一套数据结构。

## Phase 8.3: Query Diagnostics and Explain

状态：Planned。

目标：

1. 新增 `lua/obsidian-tasks/explain.lua`。
2. `explain` query 在 result buffer 中显示 query composition、filters、sorts、groups、limit、layout。
3. Query errors result 使用更结构化的错误块。
4. Preview 遇到 `explain` 时只展示短摘要，避免 virtual lines 过长。

## 当前推荐顺序

1. Phase 8.1 已完成。
2. Phase 8.2 已完成。
3. 下一步做 Phase 8.3。
