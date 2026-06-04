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

local file = root .. "/Tasks.md"
vim.fn.writefile({
  "- [ ] #task Alpha #work 📅 2026-06-05",
  "- [x] #task Done #work 📅 2026-06-04",
}, file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  queries = {
    explain = [[
explain
not done
tag includes #work
sort by due
]],
    bad = [[
explain
definitely unsupported
]],
  },
})

tasks.open_query("explain")
local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(text:find("Explain:", 1, true), text)
assert(text:find("- filters:", 1, true), text)
assert(text:find("not done", 1, true), text)
assert(text:find("tag includes #work", 1, true), text)
assert(text:find("- sorts:", 1, true), text)
assert(text:find("due", 1, true), text)
assert(text:find("Alpha", 1, true), text)
assert(not text:find("Done #work", 1, true), text)

tasks.open_query("bad")
local error_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(error_text:find("Query errors:", 1, true), error_text)
assert(error_text:find("line 2", 1, true), error_text)
assert(error_text:find("Unsupported query instruction", 1, true), error_text)
assert(error_text:find("instruction: definitely unsupported", 1, true), error_text)

local query = require("obsidian-tasks.query")
local explain = require("obsidian-tasks.explain")
local plan = query.parse("explain\nnot done\nsort by due")
assert(explain.summary(plan) == "Explain: 1 filter(s), 1 sort(s), 0 group(s)", explain.summary(plan))

local preview_file = root .. "/Query.md"
vim.fn.writefile({
  "```tasks",
  "explain",
  "not done",
  "sort by due",
  "```",
}, preview_file)
vim.cmd("edit " .. vim.fn.fnameescape(preview_file))
local preview = require("obsidian-tasks.preview")
preview.refresh_buffer(0)
local marks = vim.api.nvim_buf_get_extmarks(0, preview.namespace, 0, -1, { details = true })
local found_summary = false
for _, mark in ipairs(marks) do
  local virt_lines = mark[4] and mark[4].virt_lines or {}
  for _, virt_line in ipairs(virt_lines) do
    for _, chunk in ipairs(virt_line) do
      if chunk[1] and chunk[1]:find("Explain: 1 filter", 1, true) then
        found_summary = true
      end
    end
  end
end
assert(found_summary, vim.inspect(marks))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase8-3.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
