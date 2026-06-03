# Phase 7.5: Source Location Fidelity

目标：减少 result buffer 生命周期变长后，因为源文件行号漂移而写错任务的风险。

Phase 7.1 到 7.3 让 task cache 和 result refresh 更稳定，也意味着一个 result buffer 可能保留更久。旧 result 中保存的 `line_number` 可能因为用户在源文件插入/删除行而过期。Phase 7.5 的重点不是“尽量写成功”，而是“宁可拒绝，也不要写错行”。

## 已实现

- 新增 `lua/obsidian-tasks/source.lua`：
  - `source.signature(task)`
  - `source.enrich(task)`
  - `source.locate_in_lines(lines, task)`
  - `source.locate_in_file(task)`
  - `source.read_lines(file_path)`
  - `source.write_lines(file_path, lines)`
- task model 解析后会附带：
  - `task.source`
  - `task.source_signature`
  - `task.sourceSignature`
- 重定位顺序：
  1. 原 `line_number` 上的行仍等于 `original_markdown`。
  2. 原 `line_number` 上的行仍有同一个 `id`。
  3. 原 `line_number` 上的行仍有同一个 block link。
  4. 全文件唯一 `id`。
  5. 全文件唯一 block link。
  6. 全文件唯一 `original_markdown`。
  7. 仍无法唯一定位则拒绝。
- 接入写回路径：
  - result buffer save status changes。
  - result buffer postpone。
  - dependency editor 补 id。
  - edit form 编辑已有任务。
- result buffer `gd` / `gf` 跳源文件也会使用同一套重定位。

## 不做的事

- 不用 description 作为自动重定位依据。description 太弱，重复任务很常见。
- 不在无法定位时自动刷新 result 并重试；本阶段直接提示用户刷新。
- 不处理文件 rename/delete 的 watcher，这属于 Phase 7.4。
- 不做复杂 diff/patch 算法。

## 用户可感知行为

- 如果 result buffer 打开后源文件只是插入了新行，有 `id` 或原 markdown 仍唯一的任务可以继续安全写回。
- 如果源文件里出现重复 id，会拒绝写回，并提示重复 id。
- 如果任务没有 id，且原 markdown 已不再存在，会拒绝写回，提示刷新结果。
- `gd` / `gf` 遇到无法定位也会提示，而不是跳到旧行。

## 验收

- 旧 result buffer 中的任务在源文件插入新行后，保存状态变更不会写错行。
- 旧 result buffer 中有 id 的任务，即使原 markdown 已改动，也能按唯一 id 重定位。
- 重复 id 时拒绝写回。
- 无 id 且原 markdown 不存在时拒绝写回。
- 普通 Markdown buffer 当前行 toggle 仍按当前行工作。

## 自动测试

```sh
sh scripts/smoke_phase7_5.sh
```

建议回归：

```sh
sh scripts/smoke_phase7_3.sh
sh scripts/smoke_phase7_2.sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase5.sh
```
