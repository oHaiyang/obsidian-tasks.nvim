#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/docs", "p")
local uv = vim.uv or vim.loop
root = uv.fs_realpath(root) or root

local note = root .. "/Project.md"
vim.fn.writefile({
  "---",
  "area: work",
  "rating: 3",
  "draft: false",
  "tags: [project, focus]",
  "aliases:",
  "  - Work Note",
  "cssclasses:",
  "  - kanban",
  "TQ_show_tree: true",
  "TQ_extra_instructions: |",
  "  not done",
  "---",
  "# Project",
  "- [ ] #task Linked [[Project Alpha#Plan|Alpha]] and [Spec](docs/spec.md)",
  "- [ ] #task Plain",
}, note)

local plain = root .. "/Plain.md"
vim.fn.writefile({
  "# Plain",
  "- [ ] #task No frontmatter",
}, plain)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  enable_lua_filters = true,
})

local frontmatter = require("obsidian-tasks.frontmatter")
local links = require("obsidian-tasks.links")
local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local qfd = require("obsidian-tasks.query_file_defaults")

local props = frontmatter.parse_file(note)
assert(props.area == "work", vim.inspect(props))
assert(props.rating == 3, vim.inspect(props))
assert(props.draft == false, vim.inspect(props))
assert(props.tags[1] == "project" and props.tags[2] == "focus", vim.inspect(props.tags))
assert(props.aliases[1] == "Work Note", vim.inspect(props.aliases))
assert(props.cssclasses[1] == "kanban", vim.inspect(props.cssclasses))

local extracted = links.extract("- [ ] [[Note#Heading|Alias]] and [Label](path.md)")
assert(#extracted == 2, vim.inspect(extracted))
assert(extracted[1].type == "wiki", vim.inspect(extracted[1]))
assert(extracted[1].destination == "Note#Heading", vim.inspect(extracted[1]))
assert(extracted[1].path == "Note", vim.inspect(extracted[1]))
assert(extracted[1].subpath == "Heading", vim.inspect(extracted[1]))
assert(extracted[1].display == "Alias", vim.inspect(extracted[1]))
assert(extracted[2].type == "markdown", vim.inspect(extracted[2]))
assert(extracted[2].destination == "path.md", vim.inspect(extracted[2]))

local scanned = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
})
assert(#scanned == 3, vim.inspect(scanned))
local linked
local plain_task
for _, task in ipairs(scanned) do
  if task.description:find("Linked", 1, true) then
    linked = task
  elseif task.description:find("No frontmatter", 1, true) then
    plain_task = task
  end
end
assert(linked, vim.inspect(scanned))
assert(plain_task, vim.inspect(scanned))
assert(linked.frontmatter.area == "work", vim.inspect(linked.frontmatter))
assert(linked.properties == linked.frontmatter, vim.inspect(linked.properties))
assert(linked.file.frontmatter.area == "work", vim.inspect(linked.file))
assert(vim.tbl_contains(linked.file.tags, "project"), vim.inspect(linked.file.tags))
assert(vim.tbl_contains(linked.file.aliases, "Work Note"), vim.inspect(linked.file.aliases))
assert(vim.tbl_contains(linked.file.cssclasses, "kanban"), vim.inspect(linked.file.cssclasses))
assert(#linked.links == 2, vim.inspect(linked.links))
assert(linked.outlinks == linked.links, vim.inspect(linked.outlinks))

assert(vim.tbl_isempty(plain_task.frontmatter), vim.inspect(plain_task.frontmatter))
assert(#plain_task.links == 0, vim.inspect(plain_task.links))

local plan = query.parse([[
filter by function task.frontmatter.area == "work"
filter by function vim.tbl_contains(task.file.tags or {}, "project")
filter by function #(task.links or {}) > 0
]], { config = tasks.config })
assert(#plan.errors == 0, vim.inspect(plan.errors))
local results = query.filter_tasks(scanned, plan)
assert(#results == 1, vim.inspect(results))
assert(results[1].description:find("Linked", 1, true), results[1].description)

local query_file_plan = query.parse([[
filter by function vim.tbl_contains(query.file.tags or {}, "project")
]], {
  config = tasks.config,
  query_file_path = note,
})
assert(#query_file_plan.errors == 0, vim.inspect(query_file_plan.errors))
local query_file_results = query.filter_tasks(scanned, query_file_plan)
assert(#query_file_results == 3, vim.inspect(query_file_results))

local defaults = qfd.source({ query_file_path = note })
assert(defaults:find("show tree", 1, true), defaults)
assert(defaults:find("not done", 1, true), defaults)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase6-8.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
