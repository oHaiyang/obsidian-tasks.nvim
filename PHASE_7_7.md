# Phase 7.7: Recurrence Grammar Expansion

目标：在已有 `every day/week/month/year` 基础上，补齐 Obsidian Tasks 日常最常用的循环任务语法，让完成 recurring task 生成下一条任务时更接近原版体验。

## 已实现

1. 公开 `require("obsidian-tasks.recurrence").parse_rule(rule)`，便于后续测试、诊断和补全复用同一份 parser。
2. 保留原有基础规则：
   - `every day`
   - `every week`
   - `every month`
   - `every year`
   - `every N day/week/month/year`
   - `every other day/week/month/year`
3. 新增 weekday 规则：
   - `every weekday`
   - `every weekend`
   - `every monday` / `every mon` 等完整或缩写 weekday。
   - `every other monday` 等隔周 weekday。
   - `every week on friday`
   - `every 2 weeks on friday`
4. 新增 monthday 规则：
   - `every month on the 15th`
   - `every month on 15th`
   - `every 2 months on the 15th`
   - `every other month on 15th`
5. `when done` 继续以完成日期作为推进基准：
   - 例如 `every weekday when done`，如果完成日是周五，则下一次为下周一。
6. `every!` 已被 parser 识别为 `strict = true`：
   - 当前阶段先保留语义标记。
   - 对已有简单日期推进不额外改变行为，避免在没有完整原版语义前引入意外变化。

## 日期推进策略

Phase 7.7 仍沿用现有多日期策略：`start`、`scheduled`、`due` 各自按同一条 recurrence rule 从自身日期推进。

例子：

```markdown
- [ ] #task Review 🔁 every monday 🛫 2026-06-03 📅 2026-06-05
```

完成后：

- `start` 会从 `2026-06-03` 推到下一个 Monday。
- `due` 会从 `2026-06-05` 推到下一个 Monday。
- 如果配置了 `remove_scheduled_date_on_recurrence`，仍按已有逻辑在存在 start/due 时移除 scheduled。

这和“保持 start/due 相对间隔”的策略不同。后续如果要追更细的原版 parity，可以单独开一段实现 offset-preserving recurrence。

## 边界

- 尚未实现完整 natural-language recurrence，例如 `every month on the last Friday`、`every year on January 10`。
- `every!` 当前只解析，不提供独立 strict/non-strict 差异。
- Monthday 超出目标月份天数时会夹到月末，例如 `every month on the 31st` 从 `2026-01-31` 推到 `2026-02-28`。
- 查询语言对 recurrence 的过滤仍是字符串级能力，本阶段只处理完成任务时“生成下一条”的 recurrence 计算。

## 验证

自动 smoke：

```sh
sh scripts/smoke_phase7_7.sh
```

回归建议：

```sh
sh scripts/smoke_phase4.sh
sh scripts/smoke_phase6_7.sh
sh scripts/smoke_phase7_6.sh
```
