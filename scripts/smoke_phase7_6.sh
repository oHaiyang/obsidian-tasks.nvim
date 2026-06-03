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

local scanner_file = root .. "/Scanner.md"
vim.fn.writefile({
  "# Work",
  "",
  "- [ ] #task Visible #work",
  "",
  "```text",
  "- [ ] #task Hidden code",
  "```",
  "",
  "<!--",
  "- [ ] #task Hidden html",
  "-->",
  "",
  "%%",
  "- [ ] #task Hidden obsidian",
  "%%",
  "",
  "%% - [ ] #task Hidden inline obsidian %%",
  "",
  "> [!todo] Callout",
  "> - [ ] #task Callout task #callout",
  "",
  "> - [ ] #task Quote task #quote",
  "",
  "- [ ] #task2 Not included",
}, scanner_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  removeGlobalFilter = true,
  enable_lua_filters = true,
  queries = {
    all = "not done\nsort by description",
    by_heading = "not done\ngroup by heading",
  },
})

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")

local scanned = scanner.scan_file(scanner_file, {
  global_filter = "#task",
  remove_global_filter = true,
})
assert(#scanned == 3, vim.inspect(scanned))

local by_description = {}
for _, task in ipairs(scanned) do
  by_description[task.description] = task
  assert(task.heading == "Work", vim.inspect(task))
  assert(not task.description:find("#task", 1, true), task.description)
  assert(not vim.tbl_contains(task.tags, "#task"), vim.inspect(task.tags))
end

assert(by_description["Visible #work"], vim.inspect(scanned))
assert(by_description["Callout task #callout"], vim.inspect(scanned))
assert(by_description["Quote task #quote"], vim.inspect(scanned))
assert(vim.tbl_contains(by_description["Visible #work"].tags, "#work"), vim.inspect(by_description["Visible #work"].tags))

local callout = by_description["Callout task #callout"]
assert(callout.is_blockquote == true, vim.inspect(callout))
assert(callout.isBlockquote == true, vim.inspect(callout))
assert(callout.blockquote_depth == 1, vim.inspect(callout))
assert(callout.blockquoteDepth == 1, vim.inspect(callout))
assert(callout.callout == "todo", vim.inspect(callout))
assert(callout.list_item and callout.list_item.callout == "todo", vim.inspect(callout.list_item))

local quote = by_description["Quote task #quote"]
assert(quote.is_blockquote == true, vim.inspect(quote))
assert(quote.callout == nil, vim.inspect(quote))

local all_plan = query.parse("not done", { config = tasks.config })
local all_results = query.filter_tasks(scanned, all_plan)
assert(#all_results == 3, vim.inspect(all_results))

local blockquote_plan = query.parse("filter by function task.is_blockquote == true", {
  config = tasks.config,
  enable_lua_filters = true,
})
assert(#blockquote_plan.errors == 0, vim.inspect(blockquote_plan.errors))
local blockquote_results = query.filter_tasks(scanned, blockquote_plan)
assert(#blockquote_results == 2, vim.inspect(blockquote_results))

local callout_plan = query.parse("filter by function task.callout == \"todo\"", {
  config = tasks.config,
  enable_lua_filters = true,
})
assert(#callout_plan.errors == 0, vim.inspect(callout_plan.errors))
local callout_results = query.filter_tasks(scanned, callout_plan)
assert(#callout_results == 1, vim.inspect(callout_results))
assert(callout_results[1].description == "Callout task #callout", callout_results[1].description)

tasks.open_query("all")
local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(text:find("Visible #work", 1, true), text)
assert(text:find("Callout task #callout", 1, true), text)
assert(text:find("Quote task #quote", 1, true), text)
assert(not text:find("Hidden code", 1, true), text)
assert(not text:find("Hidden html", 1, true), text)
assert(not text:find("Hidden obsidian", 1, true), text)
assert(not text:find("Not included", 1, true), text)
assert(not text:find("#task ", 1, true), text)

tasks.open_query("by_heading")
local grouped = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(grouped:find("## Work", 1, true), grouped)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase7-6.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
