# Phase 6.4 手动测试步骤

这份文档用于手动验证 result toolbar、临时 filter 和复制结果。

## 1. 准备任务

在 vault 中新建一个 Markdown 文件，例如 `Toolbar Test.md`：

```markdown
- [ ] #task Alpha parent
  - plain child
  - [ ] #task Alpha child
- [ ] #task Beta task
```

## 2. 验证 toolbar 显示

运行 query：

```tasks
not done
show toolbar
hide backlink
```

预期 result header 中显示：

```text
Toolbar: f filter description  c clear filter  y copy markdown  Y copy with backlinks
```

如果不写 `show toolbar`，也应默认显示 toolbar。

## 3. 验证 hide toolbar

运行 query：

```tasks
not done
hide toolbar
hide backlink
```

预期：

- header 不显示 `Toolbar:` 行。
- `f` / `c` / `y` / `Y` 不作为 toolbar keymaps 绑定。

## 4. 验证临时 filter

在显示 toolbar 的 result buffer 中按：

```vim
f
```

输入：

```text
Alpha
```

预期：

- header 显示 `Filter: description includes Alpha`。
- 结果只显示 `Alpha parent` 和 `Alpha child`。
- query source 不发生变化。
- 对过滤后的 task 行执行 `<space>`、`gd`、`e`、`p` 等仍对应正确源任务。

再按：

```vim
c
```

预期恢复显示 `Beta task`。

## 5. 验证复制 Markdown

在显示 toolbar 的 result buffer 中按：

```vim
y
```

预期 unnamed register 中是 Markdown checklist，不包含 result index，也不包含 backlink：

```markdown
- [ ] #task Alpha parent
- [ ] #task Alpha child
- [ ] #task Beta task
```

再按：

```vim
Y
```

预期 copied Markdown 中 indexed task 行包含 `[[...#L...]]` backlink。

## 6. 验证 show tree copy

运行 query：

```tasks
description includes Alpha parent
show tree
show toolbar
hide backlink
```

按 `y`。

预期 copied Markdown 包含 tree context：

```markdown
- [ ] #task Alpha parent
  - plain child
  - [ ] #task Alpha child
```

## 7. Headless smoke

在插件目录运行：

```sh
sh scripts/smoke_phase6_4.sh
```
