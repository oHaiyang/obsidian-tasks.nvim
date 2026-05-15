# Phase 5.4: Result View Layout Directives

目标：让 Phase 5.3 已解析的显示类 query instructions 真正影响 Neovim result buffer 和 inline preview。

## 当前实现状态

状态：已实现第一版，手动测试步骤见 `PHASE_5_4_TEST.md`，headless smoke 见 `scripts/smoke_phase5_4.sh`。

已覆盖：

- `show task count` / `hide task count`
- `show backlink` / `hide backlink`
- `show priority` / `hide priority`
- `show tags` / `hide tags`
- `show due date` / `hide due date`
- `show scheduled date` / `hide scheduled date`
- `show start date` / `hide start date`
- `show created date` / `hide created date`
- `show done date` / `hide done date`
- `show cancelled date` / `hide cancelled date`
- `show id` / `hide id`
- `show depends on` / `hide depends on`
- `show recurrence rule` / `hide recurrence rule`
- `show on completion` / `hide on completion`

这些 directives 可以来自：

- tasks code block。
- config query。
- Query File Defaults 的 `TQ_show_*` 属性。
- `TQ_extra_instructions`。

## Result Buffer 行为

默认行为尽量保持之前的 result buffer：

- 显示 task count。
- 显示 backlink。
- 显示 priority。
- 显示 tags/date/id 等 task metadata。

当 query 中出现隐藏指令时：

```tasks
not done
hide task count
hide backlink
hide priority
hide tags
hide due date
hide id
```

结果行会隐藏对应内容。

即使 `hide backlink`，result buffer 仍然可以：

- `<space>` 切换状态。
- `<c-s>` 保存状态变更。
- `e` 编辑任务。
- `gd` / `gf` 跳回源文件。

这些操作会通过内部 `task_index_map` 找到源任务，不依赖可见 backlink。

## Inline Preview 行为

Preview 也复用同一套 layout：

```tasks
hide task count
hide backlink
hide tags
description includes Review
```

会隐藏 preview 的 `Showing n of m` 行、源文件位置，以及 task tags。

## Short Mode

`short mode` 已开始影响部分 metadata：priority、date、id、depends on、recurrence 等会优先显示符号，不显示完整值。

Neovim 里还没有 Obsidian 那样的 hover tooltip，因此 short mode 只是轻量适配，后续可以继续接 virtual text / floating detail。

## Phase 5.4 验收

- `hide task count` 隐藏 result buffer header 中的计数。
- `hide backlink` 隐藏行尾 `[[file#Lx]]`，但 toggle/save/jump/edit 仍可工作。
- `hide priority/tags/due date/id` 能从 result line 中隐藏对应字段。
- `show ...` 能显式保留对应字段。
- Preview 尊重 `hide task count`、`hide backlink`、`hide tags`。
- Phase 5.3/5.2/5.1/5/4/3/2 smoke 无回归。

## 已知限制

- `show tree` / `hide tree` 仍未实现树形子项展示。
- `show toolbar` / `hide toolbar` 目前只是被 parser 接受，真正 toolbar 放到后续。
- `show edit button` / `show postpone button` 在 Neovim 中暂时由 keymap `e` / `p` 替代。
- `show urgency` 还没有 urgency 计算。
