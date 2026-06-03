# Phase 7.6: Scanner Parity Cleanup

目标：补齐 scanner 层与功能清单中明显不一致的基础行为，让任务识别更接近 Obsidian metadata cache。

## 已实现

- Markdown code fence 内的任务继续被排除。
- 新增 HTML comment 排除：

```markdown
<!--
- [ ] #task Hidden
-->
```

- 新增 Obsidian comment 排除：

```markdown
%%
- [ ] #task Hidden
%%
```

inline `%% ... %%` 所在行也会整行跳过。

- blockquote/callout 中的任务保留 source metadata：
  - `task.is_blockquote`
  - `task.isBlockquote`
  - `task.blockquote_depth`
  - `task.blockquoteDepth`
  - `task.callout`
  - 同步到 `task.list_item`。
- `remove_global_filter` / `removeGlobalFilter`：
  - `setup()` 支持配置。
  - `scanner` / `cache` / `finder` 会传递该设置。
  - 当 global filter 是 tag，例如 `#task`，只按完整 token 删除，不误伤 `#task2`。
  - 删除发生在 task description 和 tags 提取之前，因此 `task.tags` 不再包含 global filter。

## 状态校准

Phase 7.6 也把 `FEATURES.md` 中已经实际支持的 scanner/model 能力状态调准：

- heading 已记录并可用于 query/sort/group。
- blockquote task 已支持基础扫描和 metadata。
- task tags 已有基础提取。
- block link 已解析并参与 source location。

## 当前边界

- HTML comment 采用行级跳过策略；包含 `<!--` 的行整行跳过。
- Obsidian inline comment 所在行整行跳过，不做行内部分保留。
- Callout metadata 是轻量状态：进入 callout 后，直到离开 blockquote 前都继承当前 callout type。
- 不处理完整 Obsidian metadata cache 的 section/list item 语义。
- filename-as-scheduled-date 仍未实现。

## 验收

- code fence / HTML comment / Obsidian comment 中的 task 不被扫描。
- blockquote 中 task 被扫描，并带 `is_blockquote`。
- callout 中 task 被扫描，并带 `callout`。
- heading 字段仍可用于 `group by heading` / `sort by heading`。
- `removeGlobalFilter = true` 时，description 和 tags 不再包含 `#task`。

## 自动测试

```sh
sh scripts/smoke_phase7_6.sh
```

建议回归：

```sh
sh scripts/smoke_phase7_5.sh
sh scripts/smoke_phase6_3.sh
sh scripts/smoke_phase6_8.sh
sh scripts/smoke_phase5.sh
```
