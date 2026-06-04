# Phase 8.1: Boolean Parser Hardening

目标：补齐 Phase 5.1 Boolean MVP 里缺失的 `XOR` 和更多 operand delimiter。

## 已实现

支持：

```tasks
(not done) AND (tag includes #work)
[not done] XOR [description includes someday]
{tag includes #work} OR {tag includes #home}
"description includes review" AND 'not done'
NOT [done]
```

语义：

- `AND`：左右都匹配。
- `OR`：左右任一匹配。
- `XOR`：左右恰好一个匹配。
- `NOT`：反转子表达式。

Delimiter：

- `(...)`
- `[...]`
- `{...}`
- `"..."`，支持反斜杠转义 quote。
- `'...'`，支持反斜杠转义 quote。

## 边界

- 仍不支持裸 `not done AND tag includes #work`。
- 这样是有意保守：普通 filter instruction 里可能包含 `AND` 文本，自动解析裸表达式容易误伤。
- 如果要写 Boolean，至少把 operand 包起来。

## 验证

```sh
sh scripts/smoke_phase8_1.sh
```

建议回归：

```sh
sh scripts/smoke_phase5_1.sh
sh scripts/smoke_phase5.sh
```
