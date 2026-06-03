# Phase 6.3 手动测试步骤

这份文档用于手动验证 `show tree`、`hide tree` 和 `exclude sub-items`。

## 1. 准备测试任务

在 vault 中新建一个 Markdown 文件，例如 `Tree Test.md`：

```markdown
- [ ] #task Parent
  - Planning
    - [x] Decide who to invite ✅ 2026-05-21
    - [ ] #task Child target 📅 2026-05-22
      - plain note
      - [ ] #task Grandchild
  - [ ] #task Sibling child
- [ ] #task Root sibling
> - [ ] #task Quoted root
>>  - [ ] #task Quoted sub
```

## 2. 验证默认扁平显示

运行 query：

```tasks
not done
hide backlink
```

预期：

- 只显示命中的 task 行。
- 不显示 `Planning`、`plain note` 等普通 list item。
- 子任务会被扁平展示。

## 3. 验证 show tree

运行 query：

```tasks
description includes Parent
show tree
hide backlink
```

预期：

- 显示 `Parent`。
- 展开显示 `Planning`、`Decide who to invite`、`Child target`、`plain note`、`Grandchild`、`Sibling child`。
- 只有 `Parent` 是带数字 index 的可编辑任务行。
- 子 context 行不应响应 `<space>` toggle。

再运行：

```tasks
not done
show tree
hide backlink
```

预期：

- 命中的 nested tasks 也有数字 index。
- 同一个 group 内 child task 不重复显示。
- `gd` / `gf` 可跳到带数字 index 的 task 源文件。

## 4. 验证 hide tree

运行 query：

```tasks
description includes Parent
hide tree
hide backlink
```

预期：

- 只显示 `Parent`。
- 不显示普通 child list item。

## 5. 验证 exclude sub-items

运行 query：

```tasks
not done
exclude sub-items
hide backlink
```

预期：

- 保留顶层任务：`Parent`、`Root sibling`、`Quoted root`。
- 排除缩进子任务：`Child target`、`Grandchild`、`Sibling child`、`Quoted sub`。

## 6. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase6_3.sh
```
