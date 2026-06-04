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

local file = root .. "/Project.md"
vim.fn.writefile({
  "---",
  "area: work",
  "tags: [project, active]",
  "aliases: [Query Surface]",
  "related: [[FrontmatterTarget]]",
  "---",
  "",
  "Body link [[BodyTarget]] and [External](https://example.com).",
  "",
  "- [ ] #task Frontmatter task",
  "- [ ] #task Task link [[TaskTarget]]",
}, file)

require("obsidian-tasks").setup({
  vault_path = root,
  global_filter = "#task",
})

local scanner = require("obsidian-tasks.scanner")
local query = require("obsidian-tasks.query")
local scanned = scanner.scan_file(file, {
  global_filter = "#task",
})
assert(#scanned == 2, vim.inspect(scanned))

local function descriptions(source)
  local plan = query.parse(source)
  assert(#plan.errors == 0, vim.inspect(plan.errors))
  local out = {}
  for _, task in ipairs(query.filter_tasks(scanned, plan)) do
    table.insert(out, task.description)
  end
  table.sort(out)
  return table.concat(out, ",")
end

local function expect(source, expected)
  local actual = descriptions(source)
  assert(actual == expected, source .. "\nexpected: " .. expected .. "\nactual: " .. actual)
end

assert(#(scanned[1].file.outlinks or {}) >= 3, vim.inspect(scanned[1].file.outlinks))
local both = "#task Frontmatter task,#task Task link [[TaskTarget]]"
local linked = "#task Task link [[TaskTarget]]"
expect("frontmatter.area includes work", both)
expect("property.area include work", both)
expect("file.tags includes project", both)
expect("file.aliases includes Query Surface", both)
expect("links includes TaskTarget", linked)
expect("outlinks includes TaskTarget", linked)
expect("file.outlinks includes BodyTarget", both)
expect("file.outlinks includes FrontmatterTarget", both)
expect("file.outlinks regex matches /example\\.com/", both)
expect("frontmatter.area does not include home", both)
expect("frontmatter.area does not include work", "")
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase8-2.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
