#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local display = require("obsidian-tasks.display")

local function has_line(lines, expected)
  for _, line in ipairs(lines or {}) do
    if line == expected then
      return true
    end
  end
  return false
end

local function assert_has_line(lines, expected)
  assert(has_line(lines, expected), vim.inspect(lines) .. "\nmissing: " .. expected)
end

local first_tasks = {
  { status = "[ ]", description = "#task Alpha" },
  { status = "[ ]", description = "#task Beta" },
}

local first_lines, first_index_map, next_index = display.format_task_result_section(first_tasks, {
  section_title = "First Section",
  layout = { show = { backlink = false } },
  limit = 4,
  shown_count = 4,
  total_count = 7,
})

assert_has_line(first_lines, "## First Section")
assert_has_line(first_lines, "Showing 4 of 7 tasks")
assert_has_line(first_lines, "1. [ ] #task Alpha")
assert_has_line(first_lines, "2. [ ] #task Beta")
assert(first_index_map[1] == first_tasks[1], vim.inspect(first_index_map))
assert(first_index_map[2] == first_tasks[2], vim.inspect(first_index_map))
assert(first_index_map[3] == nil, vim.inspect(first_index_map))
assert(next_index == 3, next_index)

local second_tasks = {
  { status = "[ ]", description = "#task Gamma" },
}

local second_lines, second_index_map, final_next_index = display.format_task_result_section(second_tasks, {
  section_title = "Second Section",
  layout = { show = { backlink = false } },
  startIndex = next_index,
})

assert_has_line(second_lines, "## Second Section")
assert_has_line(second_lines, "Showing 1 tasks")
assert_has_line(second_lines, "3. [ ] #task Gamma")
assert(second_index_map[2] == nil, vim.inspect(second_index_map))
assert(second_index_map[3] == second_tasks[1], vim.inspect(second_index_map))
assert(second_index_map[4] == nil, vim.inspect(second_index_map))
assert(final_next_index == 4, final_next_index)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-task-result-section.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "lua local ok, err = pcall(dofile, [[$SMOKE_LUA]]); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit') end" \
  -c "qa!"
