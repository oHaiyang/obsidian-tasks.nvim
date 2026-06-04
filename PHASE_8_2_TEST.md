# Phase 8.2 手动测试步骤

## 1. Frontmatter

准备文件：

```markdown
---
area: work
tags: [project, active]
aliases: [Query Surface]
---

- [ ] #task Frontmatter task
```

查询：

```tasks
frontmatter.area includes work
file.tags includes project
```

预期能显示该任务。

## 2. Task Links

准备任务：

```markdown
- [ ] #task Link task [[TaskTarget]]
```

查询：

```tasks
links includes TaskTarget
```

预期只匹配任务行本身包含 `[[TaskTarget]]` 的任务。

## 3. File Outlinks

同一文件任意位置添加：

```markdown
See also [[BodyTarget]].
```

查询：

```tasks
file.outlinks includes BodyTarget
```

预期该文件里的任务都可以匹配。

## 4. 自动 smoke

```sh
sh scripts/smoke_phase8_2.sh
```
