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
local project_board = root .. "/Projects/ProjectBoard.md"
local alpha = root .. "/Projects/Alpha.md"
local beta = root .. "/Projects/Beta.md"
local gamma = root .. "/Other/Gamma.md"

vim.fn.writefile({
  "# Dashboard",
  "- [ ] #task Dashboard local item",
}, dashboard)

vim.fn.writefile({
  "# Project Board",
  "```tasks",
  "# name: Project Folder",
  "# id: project-folder",
  "folder includes {{query.file.folder}}",
  "```",
  "- [ ] #task Project board local item",
}, project_board)

vim.fn.writefile({
  "# Alpha",
  "- [ ] #task Alpha project item",
}, alpha)

vim.fn.writefile({
  "# Beta",
  "- [ ] #task Beta project item",
}, beta)

vim.fn.writefile({
  "# Gamma",
  "- [ ] #task Gamma external item",
}, gamma)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  enable_lua_filters = true,
  presets = {
    dashboard_only = "path includes {{query.file.path}}",
    project_folder = "folder includes {{query.file.folder}}",
    alpha_filter = "description includes Alpha",
  },
})

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local scanned = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
})
assert(#scanned == 5, vim.inspect(scanned))

local function descriptions(results)
  local values = {}
  for _, task in ipairs(results) do
    table.insert(values, task.description)
  end
  table.sort(values)
  return table.concat(values, "\n")
end

local dashboard_plan = query.parse("path includes {{query.file.path}}", {
  config = tasks.config,
  query_file_path = dashboard,
})
assert(#dashboard_plan.errors == 0, vim.inspect(dashboard_plan.errors))
assert(dashboard_plan.expanded == "path includes " .. dashboard, dashboard_plan.expanded)
local dashboard_results = query.filter_tasks(scanned, dashboard_plan)
assert(#dashboard_results == 1, descriptions(dashboard_results))
assert(dashboard_results[1].description:find("Dashboard", 1, true), dashboard_results[1].description)

local default_preset_plan = query.parse("preset this_file", {
  config = tasks.config,
  query_file_path = dashboard,
})
assert(#default_preset_plan.errors == 0, vim.inspect(default_preset_plan.errors))
local default_preset_results = query.filter_tasks(scanned, default_preset_plan)
assert(#default_preset_results == 1, descriptions(default_preset_results))
assert(default_preset_results[1].description:find("Dashboard", 1, true), default_preset_results[1].description)

local preset_placeholder_plan = query.parse("{{preset.dashboard_only}}", {
  config = tasks.config,
  query_file_path = dashboard,
})
assert(#preset_placeholder_plan.errors == 0, vim.inspect(preset_placeholder_plan.errors))
assert(preset_placeholder_plan.expanded == "path includes " .. dashboard, preset_placeholder_plan.expanded)
local preset_placeholder_results = query.filter_tasks(scanned, preset_placeholder_plan)
assert(#preset_placeholder_results == 1, descriptions(preset_placeholder_results))
assert(preset_placeholder_results[1].description:find("Dashboard", 1, true), preset_placeholder_results[1].description)

local boolean_preset_plan = query.parse("({{preset.alpha_filter}}) OR (description includes Dashboard)", {
  config = tasks.config,
  query_file_path = dashboard,
})
assert(#boolean_preset_plan.errors == 0, vim.inspect(boolean_preset_plan.errors))
local boolean_preset_results = query.filter_tasks(scanned, boolean_preset_plan)
assert(#boolean_preset_results == 2, descriptions(boolean_preset_results))
assert(descriptions(boolean_preset_results):find("Alpha", 1, true), descriptions(boolean_preset_results))
assert(descriptions(boolean_preset_results):find("Dashboard", 1, true), descriptions(boolean_preset_results))

local source = require("obsidian-tasks.query_block").scan_file(project_board)[1]
assert(source and source.source_path == project_board, vim.inspect(source))
local block_plan = query.parse(source.query, {
  config = tasks.config,
  query_source = source,
})
assert(#block_plan.errors == 0, vim.inspect(block_plan.errors))
local block_results = query.filter_tasks(scanned, block_plan)
assert(#block_results == 4, descriptions(block_results))
assert(descriptions(block_results):find("Project board", 1, true), descriptions(block_results))
assert(not descriptions(block_results):find("Gamma", 1, true), descriptions(block_results))

local lua_context_plan = query.parse("filter by function task.file.folder == query.file.folder", {
  config = tasks.config,
  enable_lua_filters = true,
  query_file_path = project_board,
})
assert(#lua_context_plan.errors == 0, vim.inspect(lua_context_plan.errors))
local lua_context_results = query.filter_tasks(scanned, lua_context_plan)
assert(#lua_context_results == 4, descriptions(lua_context_results))
assert(not descriptions(lua_context_results):find("Gamma", 1, true), descriptions(lua_context_results))

local missing_context_plan = query.parse("path includes {{query.file.path}}", {
  config = tasks.config,
})
assert(#missing_context_plan.errors == 1, vim.inspect(missing_context_plan.errors))
assert(missing_context_plan.errors[1].message:find("no query file path", 1, true), missing_context_plan.errors[1].message)

vim.cmd("edit " .. vim.fn.fnameescape(project_board))
require("obsidian-tasks.preview").refresh_buffer(0, { limit = 2 })
local marks = vim.api.nvim_buf_get_extmarks(0, require("obsidian-tasks.preview").namespace, 0, -1, { details = true })
assert(#marks == 1, vim.inspect(marks))
local preview = vim.inspect(marks[1][4].virt_lines)
assert(preview:find("Showing 2 of 4", 1, true), preview)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-2.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
