#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/Projects", "p")

local tasks_file = root .. "/Projects/Phase5.md"
vim.fn.writefile({
  "# Phase 5",
  "- [ ] #task Alpha work item 📅 2026-05-20",
  "- [ ] #task Beta home item 📅 2026-05-21",
  "- [x] #task Done archive item ✅ 2026-05-10",
  "- [ ] #task Weekly review 🔁 every week 📅 2026-05-22 🆔 review",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  enable_lua_filters = true,
  inbox_file = tasks_file,
  presets = {
    open_alpha = [[
not done
description includes Alpha
]],
  },
  queries = {
    regex_review = [[
description regex matches /review/i
]],
    work_or_done = [[
not done
description includes work
OR
done
description includes archive
]],
    preset_alpha = [[
preset open_alpha
]],
    lua_filter = [[
filter by function task.description:find("home", 1, true) ~= nil
]],
  },
})

assert(vim.api.nvim_get_commands({}).ObsidianTasksEdit)
assert(vim.api.nvim_get_commands({}).ObsidianTasksCreate)

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local scanned = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
})

local regex_review = query.filter_tasks(scanned, query.parse("description regex matches /review/i"))
assert(#regex_review == 1, vim.inspect(regex_review))
assert(regex_review[1].description:find("Weekly review", 1, true), regex_review[1].description)

local or_query = query.filter_tasks(scanned, query.parse([[
not done
description includes work
OR
done
description includes archive
]]))
assert(#or_query == 2, vim.inspect(or_query))

local preset_query = query.filter_tasks(scanned, query.parse("preset open_alpha", { config = tasks.config }))
assert(#preset_query == 1, vim.inspect(preset_query))
assert(preset_query[1].description:find("Alpha", 1, true), preset_query[1].description)

local missing_preset = query.parse("preset missing", { config = tasks.config })
assert(#missing_preset.errors == 1, vim.inspect(missing_preset.errors))

local disabled_lua = query.parse("filter by function true", { config = { enable_lua_filters = false } })
assert(#disabled_lua.errors == 1, vim.inspect(disabled_lua.errors))

local lua_query = query.filter_tasks(scanned, query.parse(
  "filter by function task.description:find(\"home\", 1, true) ~= nil",
  { config = tasks.config, enable_lua_filters = true }
))
assert(#lua_query == 1, vim.inspect(lua_query))
assert(lua_query[1].description:find("Beta", 1, true), lua_query[1].description)

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local edit_buf = tasks.edit_current_task()
assert(edit_buf and vim.api.nvim_buf_is_valid(edit_buf))

local function set_field(buf, key, value)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local replaced = false
  for index, line in ipairs(lines) do
    if line:match("^" .. key .. ":") then
      lines[index] = key .. ": " .. value
      replaced = true
      break
    end
  end
  assert(replaced, key)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

set_field(edit_buf, "description", "Alpha edited #task")
set_field(edit_buf, "status", "In Progress")
set_field(edit_buf, "priority", "high")
set_field(edit_buf, "due", "2026-05-25")
assert(require("obsidian-tasks.edit").save_form(edit_buf))

local edited = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
assert(edited:find("%[/%]"), edited)
assert(edited:find("Alpha edited #task", 1, true), edited)
assert(edited:find("⏫", 1, true), edited)
assert(edited:find("📅 2026%-05%-25"), edited)

vim.api.nvim_win_set_cursor(0, { 2, 0 })
local create_buf = tasks.create_task()
assert(create_buf and vim.api.nvim_buf_is_valid(create_buf))
set_field(create_buf, "description", "Created from form #task")
set_field(create_buf, "status", "Todo")
set_field(create_buf, "due", "2026-05-30")
assert(require("obsidian-tasks.edit").save_form(create_buf))

local created = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(created:find("Created from form #task", 1, true), created)
assert(created:find("📅 2026%-05%-30"), created)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
