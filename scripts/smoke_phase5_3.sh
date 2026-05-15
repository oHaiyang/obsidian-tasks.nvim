#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local uv = vim.uv or vim.loop
root = uv.fs_realpath(root) or root
vim.fn.mkdir(root .. "/Projects", "p")
vim.fn.mkdir(root .. "/Other", "p")

local dashboard = root .. "/Projects/Dashboard.md"
local alpha = root .. "/Projects/Alpha.md"
local gamma = root .. "/Other/Gamma.md"
local ignore_defaults = root .. "/Other/IgnoreDefaults.md"

vim.fn.writefile({
  "---",
  "TQ_extra_instructions: |-",
  "  folder includes {{query.file.folder}}",
  "TQ_short_mode: true",
  "TQ_show_task_count: true",
  "---",
  "# Dashboard",
  "```tasks",
  "# name: Project Open",
  "# id: project-open",
  "not done",
  "sort by filename",
  "```",
  "",
  "```tasks",
  "# name: Project Open Ignoring Global",
  "# id: project-open-ignore-global",
  "ignore global query",
  "not done",
  "sort by filename",
  "```",
  "",
  "- [ ] #task Dashboard visible",
  "- [ ] #task GlobalHidden dashboard",
  "- [x] #task Dashboard done ✅ 2026-05-15",
}, dashboard)

vim.fn.writefile({
  "# Alpha",
  "- [ ] #task Alpha visible",
}, alpha)

vim.fn.writefile({
  "# Gamma",
  "- [ ] #task Gamma visible",
}, gamma)

vim.fn.writefile({
  "---",
  "TQ_extra_instructions: |-",
  "  ignore global query",
  "  folder includes {{query.file.folder}}",
  "---",
  "# Ignore Defaults",
  "```tasks",
  "# name: Defaults Ignore Global",
  "# id: defaults-ignore-global",
  "not done",
  "```",
  "",
  "- [ ] #task GlobalHidden other",
}, ignore_defaults)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  global_query = "description does not include GlobalHidden",
})

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local qfd = require("obsidian-tasks.query_file_defaults")
local sources = require("obsidian-tasks.query_block").scan_file(dashboard)
local scanned = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
})
assert(#scanned == 6, vim.inspect(scanned))

local function descriptions(results)
  local values = {}
  for _, task in ipairs(results) do
    table.insert(values, task.description)
  end
  table.sort(values)
  return table.concat(values, "\n")
end

local defaults = qfd.source({ query_file_path = dashboard })
assert(defaults:find("folder includes {{query.file.folder}}", 1, true), defaults)
assert(defaults:find("short mode", 1, true), defaults)
assert(defaults:find("show task count", 1, true), defaults)

local source = sources[1]
assert(source and source.id == "project-open", vim.inspect(sources))
local opts = {
  config = tasks.config,
  query_source = source,
}
local composition = query.compose(source.query, opts)
assert(composition.applied_global_query == true, vim.inspect(composition))
assert(composition.applied_query_file_defaults == true, vim.inspect(composition))
assert(composition.source:find("description does not include GlobalHidden", 1, true), composition.source)
assert(composition.source:find("folder includes {{query.file.folder}}", 1, true), composition.source)

local plan = query.parse(composition.source, opts)
assert(#plan.errors == 0, vim.inspect(plan.errors))
assert(plan.expanded:find("folder includes " .. root .. "/Projects/", 1, true), plan.expanded)
assert(plan.layout.short_mode == true, vim.inspect(plan.layout))
assert(plan.layout.show["task count"] == true, vim.inspect(plan.layout))
local results = query.filter_tasks(scanned, plan)
assert(#results == 2, descriptions(results))
assert(descriptions(results):find("Dashboard visible", 1, true), descriptions(results))
assert(descriptions(results):find("Alpha visible", 1, true), descriptions(results))
assert(not descriptions(results):find("GlobalHidden", 1, true), descriptions(results))
assert(not descriptions(results):find("Gamma", 1, true), descriptions(results))

local ignore_source = sources[2]
assert(ignore_source and ignore_source.id == "project-open-ignore-global", vim.inspect(sources))
local ignore_opts = {
  config = tasks.config,
  query_source = ignore_source,
}
local ignore_composition = query.compose(ignore_source.query, ignore_opts)
assert(ignore_composition.ignore_global_query == true, vim.inspect(ignore_composition))
assert(ignore_composition.applied_global_query == false, vim.inspect(ignore_composition))
assert(not ignore_composition.source:find("description does not include GlobalHidden", 1, true), ignore_composition.source)
local ignore_plan = query.parse(ignore_composition.source, ignore_opts)
assert(#ignore_plan.errors == 0, vim.inspect(ignore_plan.errors))
local ignore_results = query.filter_tasks(scanned, ignore_plan)
assert(#ignore_results == 3, descriptions(ignore_results))
assert(descriptions(ignore_results):find("GlobalHidden dashboard", 1, true), descriptions(ignore_results))
assert(not descriptions(ignore_results):find("Gamma", 1, true), descriptions(ignore_results))

local defaults_ignore_source = require("obsidian-tasks.query_block").scan_file(ignore_defaults)[1]
assert(defaults_ignore_source and defaults_ignore_source.id == "defaults-ignore-global", vim.inspect(defaults_ignore_source))
local defaults_ignore_opts = {
  config = tasks.config,
  query_source = defaults_ignore_source,
}
local defaults_ignore_composition = query.compose(defaults_ignore_source.query, defaults_ignore_opts)
assert(defaults_ignore_composition.ignore_global_query == true, vim.inspect(defaults_ignore_composition))
assert(defaults_ignore_composition.applied_global_query == false, vim.inspect(defaults_ignore_composition))
local defaults_ignore_plan = query.parse(defaults_ignore_composition.source, defaults_ignore_opts)
assert(#defaults_ignore_plan.errors == 0, vim.inspect(defaults_ignore_plan.errors))
local defaults_ignore_results = query.filter_tasks(scanned, defaults_ignore_plan)
assert(#defaults_ignore_results == 2, descriptions(defaults_ignore_results))
assert(descriptions(defaults_ignore_results):find("Gamma visible", 1, true), descriptions(defaults_ignore_results))
assert(descriptions(defaults_ignore_results):find("GlobalHidden other", 1, true), descriptions(defaults_ignore_results))

local global_ignore_composition = query.compose("description includes Alpha", {
  config = {
    global_query = "ignore global query\ndescription includes visible",
  },
  query_file_path = dashboard,
})
assert(not global_ignore_composition.global_query:find("ignore global query", 1, true), global_ignore_composition.global_query)
assert(global_ignore_composition.global_query:find("description includes visible", 1, true), global_ignore_composition.global_query)

vim.cmd("edit " .. vim.fn.fnameescape(dashboard))
require("obsidian-tasks.preview").refresh_buffer(0, { limit = 10 })
local marks = vim.api.nvim_buf_get_extmarks(0, require("obsidian-tasks.preview").namespace, 0, -1, { details = true })
assert(#marks == 2, vim.inspect(marks))
local first_preview = vim.inspect(marks[1][4].virt_lines)
local second_preview = vim.inspect(marks[2][4].virt_lines)
assert(first_preview:find("Showing 2 of 2", 1, true), first_preview)
assert(second_preview:find("Showing 3 of 3", 1, true), second_preview)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-3.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
