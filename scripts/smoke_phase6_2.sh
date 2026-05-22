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

local tasks_file = root .. "/Urgency.md"
vim.fn.writefile({
  "# Urgency",
  "```tasks",
  "# name: Preview Urgency",
  "# id: preview-urgency",
  "not done",
  "sort by urgency",
  "show urgency",
  "```",
  "",
  "- [ ] #task Highest due today 🔺 📅 2026-05-16",
  "- [ ] #task Medium due today 🔼 📅 2026-05-16",
  "- [ ] #task High scheduled started ⏫ 🛫 2026-05-15 ⏳ 2026-05-15",
  "- [ ] #task Low future 🔽 📅 2026-06-16",
  "- [ ] #task Normal no date",
  "- [ ] #task Lowest no date ⏬",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
  enable_lua_filters = true,
  queries = {
    urgency_sorted = [[
not done
sort by urgency
show urgency
]],
    urgency_reverse = [[
not done
sort by urgency reverse
show urgency
]],
    urgency_hidden = [[
not done
sort by urgency
hide urgency
]],
    urgency_short = [[
not done
sort by urgency
short mode
show urgency
]],
  },
})

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local sorter = require("obsidian-tasks.sort")
local parser = require("obsidian-tasks.parser")
local urgency = require("obsidian-tasks.urgency")

local function approx(actual, expected)
  return math.abs(actual - expected) < 0.0001
end

local scanned = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
})
assert(#scanned == 6, vim.inspect(scanned))
assert(approx(scanned[1].urgency, 17.8), scanned[1].urgency)
assert(approx(scanned[2].urgency, 12.7), scanned[2].urgency)
assert(approx(scanned[3].urgency, 11.0), scanned[3].urgency)
assert(approx(scanned[4].urgency, 2.4), scanned[4].urgency)
assert(approx(scanned[5].urgency, 1.95), scanned[5].urgency)
assert(approx(scanned[6].urgency, -1.8), scanned[6].urgency)
assert(urgency.format(scanned[1]) == "17.80", urgency.format(scanned[1]))

local sorted_plan = query.parse("not done\nsort by urgency\nshow urgency", { config = tasks.config })
assert(#sorted_plan.errors == 0, vim.inspect(sorted_plan.errors))
assert(sorted_plan.layout.show.urgency == true, vim.inspect(sorted_plan.layout))
local sorted = sorter.apply(query.filter_tasks(scanned, sorted_plan), sorted_plan.sorts)
assert(sorted[1].description:find("Highest", 1, true), vim.inspect(sorted))
assert(sorted[#sorted].description:find("Lowest", 1, true), vim.inspect(sorted))

local reverse_plan = query.parse("not done\nsort by urgency reverse", { config = tasks.config })
assert(#reverse_plan.errors == 0, vim.inspect(reverse_plan.errors))
local reversed = sorter.apply(query.filter_tasks(scanned, reverse_plan), reverse_plan.sorts)
assert(reversed[1].description:find("Lowest", 1, true), vim.inspect(reversed))
assert(reversed[#reversed].description:find("Highest", 1, true), vim.inspect(reversed))

local group_plan = query.parse("not done\ngroup by urgency", { config = tasks.config })
assert(#group_plan.errors == 0, vim.inspect(group_plan.errors))
local grouped, group_order = parser.group_tasks(query.filter_tasks(scanned, group_plan), group_plan.group_by)
assert(group_order[1] == "17.80", vim.inspect(group_order))
assert(group_order[#group_order] == "-1.80", vim.inspect(group_order))
assert(#grouped["17.80"] == 1, vim.inspect(grouped))

local function_plan = query.parse([[
filter by function task.urgency > 10
sort by urgency
]], { config = tasks.config, enable_lua_filters = true })
assert(#function_plan.errors == 0, vim.inspect(function_plan.errors))
local function_results = sorter.apply(query.filter_tasks(scanned, function_plan), function_plan.sorts)
assert(#function_results == 3, vim.inspect(function_results))
assert(function_results[1].description:find("Highest", 1, true), vim.inspect(function_results))

local function current_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function find_line(pattern)
  for index, line in ipairs(current_lines()) do
    if line:find(pattern, 1, true) then
      return index, line
    end
  end
  return nil, nil
end

tasks.open_query("urgency_sorted")
local highest_row, highest_line = find_line("Highest due today")
local medium_row, medium_line = find_line("Medium due today")
assert(highest_row and medium_row and highest_row < medium_row, table.concat(current_lines(), "\n"))
assert(highest_line:find("urgency 17.80", 1, true), highest_line)
assert(medium_line:find("urgency 12.70", 1, true), medium_line)

tasks.open_query("urgency_reverse")
local lowest_row, lowest_line = find_line("Lowest no date")
highest_row = find_line("Highest due today")
assert(lowest_row and highest_row and lowest_row < highest_row, table.concat(current_lines(), "\n"))
assert(lowest_line:find("urgency %-1%.80"), lowest_line)

tasks.open_query("urgency_hidden")
_, highest_line = find_line("Highest due today")
assert(highest_line and not highest_line:find("urgency", 1, true), highest_line)
assert(not highest_line:find("17.80", 1, true), highest_line)

tasks.open_query("urgency_short")
_, highest_line = find_line("Highest due today")
assert(highest_line:find("17.80", 1, true), highest_line)
assert(not highest_line:find("urgency", 1, true), highest_line)

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
require("obsidian-tasks.preview").refresh_buffer(0, { limit = 2, today = "2026-05-16" })
local marks = vim.api.nvim_buf_get_extmarks(0, require("obsidian-tasks.preview").namespace, 0, -1, { details = true })
assert(#marks == 1, vim.inspect(marks))
local preview = vim.inspect(marks[1][4].virt_lines)
assert(preview:find("urgency 17.80", 1, true), preview)
assert(preview:find("urgency 12.70", 1, true), preview)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase6-2.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
