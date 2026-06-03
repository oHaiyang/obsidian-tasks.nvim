# Phase 7.5 手动测试步骤

这份文档用于手动验证 source location fidelity。

## 1. 配置

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/vault",
  global_filter = "#task",
  cache = {
    enabled = true,
    auto_update_on_write = true,
  },
  queries = {
    all = "not done",
  },
})
```

## 2. 准备文件

`Tasks.md`：

```markdown
# Tasks

- [ ] #task Alpha 🆔 alpha-id
- [ ] #task Beta
```

## 3. 打开 result

```vim
:ObsidianTasksRefreshCache
:ObsidianTasks all
```

保持 result buffer 打开。

## 4. 源文件插入新行后仍能写回

打开 `Tasks.md`，在 Alpha 上方插入：

```markdown
- [ ] #task Inserted
```

保存后回到 result buffer，不刷新 result。把 Alpha 改成 done 并保存 result：

```vim
<space>
<C-S>
```

预期：

- Alpha 被写成 done。
- Inserted 没有被错误改动。

## 5. 有 id 时可在原 markdown 改动后重定位

继续保持旧 result buffer。到源文件把 Alpha 文本改成：

```markdown
- [ ] #task Alpha renamed 🆔 alpha-id
```

回到旧 result buffer，对 Alpha 执行 postpone 或 status save。

预期按 `alpha-id` 定位到 Alpha renamed。

## 6. 重复 id 时拒绝

在源文件新增另一条：

```markdown
- [ ] #task Duplicate 🆔 alpha-id
```

回到旧 result buffer 对 Alpha 保存变更。

预期插件拒绝写回，并提示多个任务有相同 id。

## 7. 无 id 且原 markdown 不存在时拒绝

打开 result 后，把 Beta 源文件行改成完全不同内容，例如：

```markdown
- [ ] #task Beta renamed
```

回到旧 result buffer 对 Beta 保存变更。

预期插件拒绝写回，提示刷新结果。

## 8. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase7_5.sh
```

建议再跑：

```sh
sh scripts/smoke_phase7_3.sh
sh scripts/smoke_phase7_2.sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase5.sh
```
