# Phase 8.1 手动测试步骤

## 1. XOR

查询：

```tasks
[tag includes #work] XOR [tag includes #home]
```

准备任务：

```markdown
- [ ] #task Work only #work
- [ ] #task Home only #home
- [ ] #task Both #work #home
- [ ] #task Neither
```

预期只显示 `Work only` 和 `Home only`。

## 2. Bracket / Brace / Quote Delimiters

查询：

```tasks
{not done} AND "description includes Review"
```

预期只显示未完成且描述包含 `Review` 的任务。

## 3. NOT

查询：

```tasks
NOT [done]
```

预期显示未完成任务。

## 4. 自动 smoke

```sh
sh scripts/smoke_phase8_1.sh
```
