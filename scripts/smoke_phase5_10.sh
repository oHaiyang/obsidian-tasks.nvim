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

local no_defaults = root .. "/NoDefaults.md"
local existing_defaults = root .. "/ExistingDefaults.md"

vim.fn.writefile({
  "# No Defaults",
  "",
  "```tasks",
  "not done",
  "```",
}, no_defaults)

vim.fn.writefile({
  "---",
  "title: Existing Defaults",
  "TQ_extra_instructions: |-",
  "  folder includes Projects",
  "TQ_show_tree: true",
  "---",
  "# Existing Defaults",
}, existing_defaults)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
})

local qfd = require("obsidian-tasks.query_file_defaults")
local property_names = qfd.all_property_names_sorted()

local function count_matching(lines, pattern)
  local count = 0
  for _, line in ipairs(lines) do
    if line:match(pattern) then
      count = count + 1
    end
  end
  return count
end

assert(#property_names == 22, vim.inspect(property_names))
assert(property_names[1] == "TQ_explain", vim.inspect(property_names))
assert(property_names[#property_names] == "TQ_show_urgency", vim.inspect(property_names))

local no_frontmatter_lines = vim.fn.readfile(no_defaults)
local added_lines, added_count = qfd.add_all_properties_to_lines(no_frontmatter_lines)
assert(added_count == #property_names, added_count)
assert(added_lines[1] == "---", vim.inspect(added_lines))
for index, name in ipairs(property_names) do
  assert(added_lines[index + 1] == name .. ":", added_lines[index + 1])
end
assert(added_lines[#property_names + 2] == "---", added_lines[#property_names + 2])
assert(added_lines[#property_names + 3] == "", vim.inspect(added_lines))
assert(added_lines[#property_names + 4] == "# No Defaults", vim.inspect(added_lines))

local existing_lines = vim.fn.readfile(existing_defaults)
local updated_existing, existing_added_count = qfd.add_all_properties_to_lines(existing_lines)
assert(existing_added_count == #property_names - 2, existing_added_count)
assert(count_matching(updated_existing, "^TQ_show_tree:") == 1, vim.inspect(updated_existing))
assert(count_matching(updated_existing, "^TQ_extra_instructions:") == 1, vim.inspect(updated_existing))
assert(vim.tbl_contains(updated_existing, "TQ_show_tree: true"), vim.inspect(updated_existing))
assert(vim.tbl_contains(updated_existing, "  folder includes Projects"), vim.inspect(updated_existing))
assert(vim.tbl_contains(updated_existing, "# Existing Defaults"), vim.inspect(updated_existing))
local _, repeat_added_count = qfd.add_all_properties_to_lines(updated_existing)
assert(repeat_added_count == 0, repeat_added_count)

assert(vim.fn.exists(":ObsidianTasksAddQueryFileDefaults") == 2)
assert(vim.fn.exists(":ObsidianTasksAddQueryFileDefaultsProperties") == 2)

vim.cmd("edit " .. vim.fn.fnameescape(no_defaults))
local command_added_count = tasks.add_query_file_defaults_properties()
assert(command_added_count == #property_names, command_added_count)
local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(buffer_lines[1] == "---", vim.inspect(buffer_lines))
assert(buffer_lines[#property_names + 4] == "# No Defaults", vim.inspect(buffer_lines))
assert(tasks.add_query_file_defaults_properties() == 0)

vim.cmd("edit! " .. vim.fn.fnameescape(existing_defaults))
local existing_command_added_count = qfd.add_all_properties_to_buffer(0)
assert(existing_command_added_count == #property_names - 2, existing_command_added_count)
assert(qfd.add_all_properties_to_buffer(0) == 0)
vim.cmd("write")

local defaults_source = qfd.source({ query_file_path = existing_defaults })
assert(defaults_source:find("folder includes Projects", 1, true), defaults_source)
assert(defaults_source:find("show tree", 1, true), defaults_source)
assert(not defaults_source:find("explain", 1, true), defaults_source)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase5-10.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
