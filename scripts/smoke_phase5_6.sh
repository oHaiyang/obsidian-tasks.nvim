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

local tasks_file = root .. "/Form.md"
vim.fn.writefile({
  "# Form",
  "- [ ] #task Existing dependency 🆔 alpha-id",
  "- [ ] #task Another dependency 🆔 beta-id",
  "- [ ] #task Target task",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
  auto_suggest_in_editor = true,
  auto_suggest_min_chars = 0,
  auto_suggest_max_items = 20,
  status_settings = {
    { symbol = " ", name = "Todo", type = "TODO", next_symbol = "/" },
    { symbol = "/", name = "In Progress", type = "IN_PROGRESS", next_symbol = "x" },
    { symbol = "?", name = "Waiting", type = "ON_HOLD", next_symbol = "x" },
    { symbol = "x", name = "Done", type = "DONE", next_symbol = " " },
  },
})

local edit = require("obsidian-tasks.edit")

local function has_word(items, word)
  for _, item in ipairs(items) do
    if item.word == word then
      return true
    end
  end
  return false
end

local function find_word(items, word)
  for _, item in ipairs(items) do
    if item.word == word then
      return item
    end
  end
  return nil
end

local function field_row(buf, key)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:match("^" .. key .. ":") then
      return index
    end
  end
  error("field not found: " .. key)
end

local function set_field(buf, key, value)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:match("^" .. key .. ":") then
      lines[index] = key .. ": " .. value
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      return index
    end
  end
  error("field not found: " .. key)
end

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
vim.api.nvim_win_set_cursor(0, { 4, 0 })
local buf = tasks.edit_current_task()
assert(buf and vim.api.nvim_buf_is_valid(buf))
local state = edit.form_state[buf]
assert(state)
local completeopt = vim.api.nvim_get_option_value("completeopt", { buf = buf })
assert(completeopt:find("noinsert", 1, true), completeopt)
assert(completeopt:find("noselect", 1, true), completeopt)

assert(has_word(edit.suggest_field("status", "W", state), "Waiting"))
assert(has_word(edit.suggest_field("priority", "h", state), "highest"))
assert(has_word(edit.suggest_field("priority", "h", state), "high"))
local tomorrow_item = find_word(edit.suggest_field("due", "tom", state), "2026-05-17")
assert(tomorrow_item, vim.inspect(edit.suggest_field("due", "tom", state)))
assert(tomorrow_item.filter_text == "tomorrow", vim.inspect(tomorrow_item))
assert(tomorrow_item.abbr:find("tomorrow", 1, true), tomorrow_item.abbr)
assert(has_word(edit.suggest_field("recurrence", "every w", state), "every week"))
assert(has_word(edit.suggest_field("on_completion", "d", state), "delete"))
assert(has_word(edit.suggest_field("depends_on", "alpha", state), "alpha-id"))
assert(has_word(edit.suggest_field("depends_on", "beta", state), "beta-id"))
assert(has_word(edit.suggest_field("id", "task", state), "task-20260516"))

vim.api.nvim_set_current_buf(buf)
local row = set_field(buf, "priority", "h")
vim.api.nvim_win_set_cursor(0, { row, #"priority: h" })
assert(edit.complete(1, "h") == #"priority: ")
assert(has_word(edit.complete(0, "h"), "high"))

row = set_field(buf, "depends_on", "alpha-id, b")
vim.api.nvim_win_set_cursor(0, { row, #"depends_on: alpha-id, b" })
assert(edit.complete(1, "b") == #"depends_on: alpha-id, ")
assert(has_word(edit.complete(0, "b"), "beta-id"))

row = set_field(buf, "done", "to")
vim.api.nvim_win_set_cursor(0, { row, #"done: to" })
assert(edit.complete(1, "to") == #"done: ")
assert(has_word(edit.complete(0, "to"), "2026-05-16"))
set_field(buf, "done", "")

row = set_field(buf, "priority", "high")
vim.api.nvim_win_set_cursor(0, { row, #"priority: high" })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A<BS><Esc>", true, false, true), "xt", false)
vim.wait(50, function()
  return false
end)
local priority_line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
assert(priority_line == "priority: hig", priority_line)

tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
  auto_suggest_max_items = 1,
})
assert(#edit.suggest_field("priority", "", state) == 1)

tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
  auto_suggest_in_editor = true,
  status_settings = {
    { symbol = " ", name = "Todo", type = "TODO", next_symbol = "/" },
    { symbol = "/", name = "In Progress", type = "IN_PROGRESS", next_symbol = "x" },
    { symbol = "?", name = "Waiting", type = "ON_HOLD", next_symbol = "x" },
    { symbol = "x", name = "Done", type = "DONE", next_symbol = " " },
  },
})
set_field(buf, "status", "Waiting")
set_field(buf, "priority", "high")
set_field(buf, "due", "tomorrow")
set_field(buf, "recurrence", "every week")
set_field(buf, "id", "task-20260516")
set_field(buf, "depends_on", "alpha-id, beta-id")
set_field(buf, "on_completion", "keep")
assert(edit.save_form(buf))

local saved = vim.api.nvim_buf_get_lines(0, 3, 4, false)[1]
assert(saved:find("%[%?%]"), saved)
assert(saved:find("⏫", 1, true), saved)
assert(saved:find("🔁 every week", 1, true), saved)
assert(saved:find("🏁 keep", 1, true), saved)
assert(saved:find("📅 2026-05-17", 1, true), saved)
assert(saved:find("🆔 task-20260516", 1, true), saved)
assert(saved:find("⛔ alpha-id, beta-id", 1, true), saved)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-6.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
