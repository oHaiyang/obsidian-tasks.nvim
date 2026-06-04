# Phase 8.2: File, Frontmatter, and Link Query Surface

目标：把 Phase 6.8 已暴露给 Lua function 的 file/frontmatter/link 数据，提升为普通 query instruction 可直接使用的字段。

## 已实现

新增可查询字段：

- `frontmatter.<key>`
- `properties.<key>`
- `property.<key>`
- `file.frontmatter.<key>`
- `file.properties.<key>`
- `file.tags`
- `file.aliases`
- `file.classes`
- `file.cssclasses`
- `links`
- `outlinks`
- `file.links`
- `file.outlinks`

支持操作：

```tasks
frontmatter.area includes work
property.project does not include archive
file.tags includes project
links includes Target Note
file.outlinks regex matches /Target|Reference/
```

同时支持 `include` 和 `includes` 两种写法。

## File Outlinks

Scanner 现在会提取整篇 Markdown 文件中的 wikilink 和 Markdown link，并写入：

- `task.file.links`
- `task.file.outlinks`
- `task.file_links`
- `task.file_outlinks`

`task.links` / `task.outlinks` 仍表示 task line 自身的链接。

## 边界

- Frontmatter parser 仍是轻量 YAML subset；JSON frontmatter 暂未实现。
- `frontmatter.<key>` 当前按点号访问 table path；带点号的 property key 还不能直接区分。
- Link 查询以 link destination/path/display/raw 文本拼接后匹配，不做 Obsidian 路径解析或别名反解。

## 验证

```sh
sh scripts/smoke_phase8_2.sh
```

建议回归：

```sh
sh scripts/smoke_phase6_8.sh
sh scripts/smoke_phase7_6.sh
sh scripts/smoke_phase8_1.sh
```
