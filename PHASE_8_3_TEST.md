# Phase 8.3 手动测试步骤

## 1. Result Explain

创建 query：

```tasks
explain
not done
tag includes #work
sort by due
```

打开 query result。

预期 result header 下方出现：

```text
Explain:
- filters:
  - not done
  - tag includes #work
- sorts:
  - due
```

## 2. Query Error

运行错误 query：

```tasks
explain
unknown instruction
```

预期打开错误 buffer，并显示：

```text
Query errors:
- line 2: Unsupported query instruction
  instruction: unknown instruction
```

## 3. Preview

在 Markdown query block 中写：

````markdown
```tasks
explain
not done
sort by due
```
````

执行：

```vim
:ObsidianTasksPreviewToggle
```

预期 virtual lines 中出现短摘要：

```text
Explain: 1 filter(s), 1 sort(s), 0 group(s)
```

## 4. 自动 smoke

```sh
sh scripts/smoke_phase8_3.sh
```
