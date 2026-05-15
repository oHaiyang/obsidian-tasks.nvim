# Phase 5.1: Boolean Query Expressions

目标：把 Phase 5 的独立行 `OR` 升级为括号 Boolean 表达式，让 query 写法更接近 Obsidian Tasks。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_5_1_TEST.md`，headless smoke 见 `scripts/smoke_phase5_1.sh`。

已覆盖：

- `(filter A) AND (filter B)`
- `(filter A) OR (filter B)`
- `NOT (filter A)`
- `(filter A) AND NOT (filter B)`
- 嵌套表达式：

```tasks
(not done) AND ((tag includes #work) OR (tag includes #home))
```

- Boolean 表达式可以和普通多行 query 混用：

```tasks
not done
(tag includes #work) OR (tag includes #home)
sort by due
```

仍留到后续：

- `XOR`
- bracket / quote delimiters
- 更完整的错误 explain
- `{{preset.name}}` 在 Boolean 内展开

## 语法

每个 Boolean operand 建议用括号包住：

```tasks
(not done) AND (priority is above normal)
```

支持嵌套：

```tasks
(not done) AND ((description includes work) OR (description includes home))
```

支持 NOT：

```tasks
NOT (done)
```

支持 AND NOT：

```tasks
(not done) AND NOT (description includes someday)
```

## 和普通 query 的关系

多行 query 仍然默认是 AND：

```tasks
not done
(tag includes #work) OR (tag includes #home)
due on or before tomorrow
```

含义是：

```tasks
not done
AND ((tag includes #work) OR (tag includes #home))
AND due on or before tomorrow
```

Phase 5 的独立行 `OR` 仍保留：

```tasks
not done
tag includes #work
OR
done
tag includes #archive
```

但后续建议优先使用括号 Boolean，因为它更清晰、更接近原插件文档。

## 错误提示

会对以下情况给出 query error：

- 括号不匹配。
- `AND` / `OR` 缺少左右 filter。
- `NOT` 后没有 filter。
- Boolean operand 不能解析成单个 filter。

## Phase 5.1 验收

- AND / OR / NOT / AND NOT 能过滤出正确任务。
- 嵌套 Boolean 表达式能过滤出正确任务。
- Boolean 表达式可以和 regex、function filter、普通多行 query 混用。
- 无效 Boolean 表达式能显示错误。
- Phase 5/4/3/2 smoke 无回归。
