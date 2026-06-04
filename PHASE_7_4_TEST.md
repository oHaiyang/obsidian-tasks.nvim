# Phase 7.4 手动测试步骤

目标：验证 cache watcher 能处理外部创建、修改、删除 Markdown 文件，并且不会在 watcher 不可用时破坏已有功能。

## 1. 启用 watcher

在测试配置里启用：

```lua
require("obsidian-tasks").setup({
  vault_path = "/path/to/test-vault",
  global_filter = "#task",
  cache = {
    enabled = true,
    watch = true,
    watch_debounce_ms = 100,
  },
})
```

打开 Neovim 后执行：

```vim
:ObsidianTasksRefreshCache
:ObsidianTasksCacheInfo
```

预期：

- cache 状态为 `warm`。
- watcher 显示 `running`，或在系统不支持时显示 `unavailable`。
- 如果是 `unavailable`，这不是失败；说明当前环境不能使用 libuv recursive watcher，需要继续依赖保存更新或手动 refresh。

## 2. 外部创建文件

在 Neovim 外部创建：

```markdown
# External

- [ ] #task Created outside
```

回到 Neovim，执行：

```vim
:ObsidianTasksCacheInfo
```

然后刷新当前 query result：

```vim
:ObsidianTasksRefresh
```

预期：query result 能看到 `Created outside`。

如果 watcher 状态不是 `running`，需要用：

```vim
:ObsidianTasksRefreshCache!
```

## 3. 外部修改文件

在外部把任务改成：

```markdown
- [ ] #task Updated outside
```

回到 Neovim，刷新 result：

```vim
:ObsidianTasksRefresh
```

预期：旧描述消失，新描述出现。

## 4. 外部删除文件

在外部删除刚才的 Markdown 文件。

回到 Neovim，刷新 result：

```vim
:ObsidianTasksRefresh
```

预期：该文件里的任务从结果中消失。

## 5. 手动停止/启动 watcher

执行：

```vim
:ObsidianTasksStopCacheWatcher
:ObsidianTasksCacheInfo
```

预期 watcher 显示 `stopped`。

再执行：

```vim
:ObsidianTasksStartCacheWatcher
:ObsidianTasksCacheInfo
```

预期 watcher 回到 `running`，或显示 `unavailable`。

## 6. 自动 smoke

在插件目录执行：

```sh
sh scripts/smoke_phase7_4.sh
```
