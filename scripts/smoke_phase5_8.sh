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

local tasks_file = root .. "/Complete.md"
vim.fn.writefile({
  "# Complete",
  "- [ ] #task Existing dependency 🆔 alpha-id",
  "- [ ] #task Another dependency 🆔 beta-id",
  "- [ ] #task Due field 📅 tom",
  "- [ ] #task Recurring field 🔁 every w",
  "- [ ] #task Depends field ⛔ alpha-id, b",
  "- [ ] #task Priority field h",
  "Plain paragraph 📅 tom",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-16",
  completion = {
    cmp = true,
  },
})

local cmp_source = require("obsidian-tasks.completion.cmp")
local source = cmp_source.new()

local function complete_line(line, before, filetype)
  local response
  source:complete({
    context = {
      bufnr = 0,
      row = 1,
      filetype = filetype or "markdown",
      cursor_line = line,
      cursor_before_line = before or line,
    },
  }, function(result)
    response = result
  end)
  assert(response)
  return response
end

local function has_insert(items, text)
  for _, item in ipairs(items) do
    if item.insertText == text then
      return true, item
    end
  end
  return false, nil
end

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))

local response = complete_line("- [ ] #task Due field 📅 tom")
local ok, item = has_insert(response.items, "2026-05-17")
assert(ok, vim.inspect(response.items))
assert(item.filterText == "tomorrow", vim.inspect(item))
assert(response.offset and response.offset > 1, vim.inspect(response))

response = complete_line("- [ ] #task Recurring field 🔁 every w")
assert(has_insert(response.items, "every week"))

response = complete_line("- [ ] #task Depends field ⛔ alpha-id, b")
assert(has_insert(response.items, "beta-id"))

response = complete_line("- [ ] #task Priority field h")
assert(has_insert(response.items, "⏫"))

response = complete_line("Plain paragraph 📅 tom")
assert(#response.items == 0, vim.inspect(response.items))

response = complete_line("priority: h", "priority: h", "obstasks-form")
assert(has_insert(response.items, "high"))
assert(has_insert(response.items, "highest"))

response = complete_line("due: tom", "due: tom", "obstasks-form")
assert(has_insert(response.items, "tomorrow"))

response = complete_line("depends_on: b", "depends_on: b", "obstasks-form")
assert(has_insert(response.items, "beta-id"))

assert(cmp_source.register({ name = "obsidian-tasks-test" }) == false)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-8.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
