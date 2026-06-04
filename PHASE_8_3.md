# Phase 8.3: Query Diagnostics and Explain

目标：让 `explain` 不再只是被 parser 接受，而是在 result buffer、错误页和 preview 中给出可读诊断信息。

## 已实现

1. 新增 `lua/obsidian-tasks/explain.lua`：
   - `explain.lines(plan, opts)`
   - `explain.error_lines(errors, opts)`
   - `explain.summary(plan)`
2. Result buffer：
   - query 包含 `explain` 时，在 header 和 task lines 之间插入 explain block。
   - 展示 global query / query file defaults 是否应用。
   - 展示 filters / sorts / groups / limit / layout 摘要。
3. Query error buffer：
   - 使用结构化 `Query errors:` block。
   - 显示出错行号、错误信息、原 instruction。
   - 如果有 query composition 信息，也显示 global query / query file defaults 状态。
4. Preview：
   - 遇到 `explain` 时只显示短摘要，例如 `Explain: 2 filter(s), 1 sort(s), 0 group(s)`。
   - 避免 virtual lines 过长。

## 边界

- Explain 目前是轻量摘要，不是原版逐 token/逐日期展开的完整解释。
- Date expression 的具体展开值已经体现在 parsed filter 中，但不逐步解释自然语言解析过程。
- Boolean expression 目前显示为 `Boolean expression` 摘要，不展开整棵 AST。

## 验证

```sh
sh scripts/smoke_phase8_3.sh
```

建议回归：

```sh
sh scripts/smoke_phase7_3.sh
sh scripts/smoke_phase8_1.sh
sh scripts/smoke_phase8_2.sh
```
