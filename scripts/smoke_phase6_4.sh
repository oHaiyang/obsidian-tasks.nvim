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

local tasks_file = root .. "/Toolbar.md"
vim.fn.writefile({
  "# Toolbar",
  "- [ ] #task Alpha parent",
  "  - plain child",
  "  - [ ] #task Alpha child",
  "- [ ] #task Beta task",
}, tasks_file)

require("obsidian-tasks").setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-22",
})

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local parser = require("obsidian-tasks.parser")
local display = require("obsidian-tasks.display")
local core = require("obsidian-tasks.core")

local function has_line(lines, expected)
  for _, line in ipairs(lines or {}) do
    if line == expected then
      return true
    end
  end
  return false
end

local function has_prefix(lines, prefix)
  for _, line in ipairs(lines or {}) do
    if line:find(prefix, 1, true) == 1 then
      return true
    end
  end
  return false
end

local function buffer_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function render(source)
  local tasks = scanner.scan_vault({
    vault_path = root,
    global_filter = "#task",
    today = "2026-05-22",
  })
  local plan = query.parse(source, { today = "2026-05-22" })
  assert(#plan.errors == 0, vim.inspect(plan.errors))
  local filtered = query.filter_tasks(tasks, plan)
  local grouped, order = parser.group_tasks(filtered, plan.group_by or {})
  display.display_tasks(filtered, grouped, order, {
    layout = plan.layout,
    query_plan = plan,
    group_by = plan.group_by or {},
    query_name = "Toolbar smoke",
    total_count = #filtered,
    shown_count = #filtered,
  })
  return vim.api.nvim_get_current_buf(), filtered
end

local buf = render("not done\nshow toolbar\nhide backlink")
local lines = buffer_lines(buf)
assert(has_prefix(lines, "Toolbar:"), vim.inspect(lines))
assert((vim.fn.maparg("f", "n", false, true) or {}).buffer == 1, vim.inspect(vim.fn.maparg("f", "n", false, true)))
assert(has_line(lines, "1. [ ] #task Alpha parent"), vim.inspect(lines))
assert(has_line(lines, "2. [ ] #task Alpha child"), vim.inspect(lines))
assert(has_line(lines, "3. [ ] #task Beta task"), vim.inspect(lines))

assert(display.set_toolbar_filter(buf, "Alpha"))
lines = buffer_lines(buf)
assert(has_prefix(lines, "Filter: description includes Alpha"), vim.inspect(lines))
assert(has_line(lines, "1. [ ] #task Alpha parent"), vim.inspect(lines))
assert(has_line(lines, "2. [ ] #task Alpha child"), vim.inspect(lines))
assert(not has_line(lines, "3. [ ] #task Beta task"), vim.inspect(lines))
assert(core.task_index_map[buf][1].description == "#task Alpha parent", vim.inspect(core.task_index_map[buf]))
assert(core.task_index_map[buf][2].description == "#task Alpha child", vim.inspect(core.task_index_map[buf]))

local copied = display.copy_markdown(buf, { include_backlinks = false, register = "a" })
assert(has_line(copied, "- [ ] #task Alpha parent"), vim.inspect(copied))
assert(has_line(copied, "- [ ] #task Alpha child"), vim.inspect(copied))
assert(not table.concat(copied, "\n"):find("%[%["), vim.inspect(copied))
assert(vim.fn.getreg("a") == table.concat(copied, "\n"), vim.fn.getreg("a"))

local copied_with_backlinks = display.copy_markdown(buf, { include_backlinks = true, register = "b" })
local joined_with_backlinks = table.concat(copied_with_backlinks, "\n")
assert(joined_with_backlinks:find("Toolbar.md#L2", 1, true), joined_with_backlinks)
assert(joined_with_backlinks:find("Toolbar.md#L4", 1, true), joined_with_backlinks)

assert(display.clear_toolbar_filter(buf))
lines = buffer_lines(buf)
assert(not has_prefix(lines, "Filter:"), vim.inspect(lines))
assert(has_line(lines, "3. [ ] #task Beta task"), vim.inspect(lines))

buf = render("description includes Alpha parent\nshow tree\nshow toolbar\nhide backlink")
local tree_copy = display.markdown_lines(buf, { include_backlinks = false })
assert(has_line(tree_copy, "- [ ] #task Alpha parent"), vim.inspect(tree_copy))
assert(has_line(tree_copy, "  - plain child"), vim.inspect(tree_copy))
assert(has_line(tree_copy, "  - [ ] #task Alpha child"), vim.inspect(tree_copy))

buf = render("not done\nhide toolbar\nhide backlink")
lines = buffer_lines(buf)
assert(not has_prefix(lines, "Toolbar:"), vim.inspect(lines))
assert(vim.fn.maparg("f", "n") == "", vim.inspect(vim.fn.maparg("f", "n", false, true)))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase6-4.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
