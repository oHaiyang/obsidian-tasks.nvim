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

local tasks_file = root .. "/Tree.md"
vim.fn.writefile({
  "# Tree",
  "- [ ] #task Parent",
  "  - Planning",
  "    - [x] Decide who to invite ✅ 2026-05-21",
  "    - [ ] #task Child target 📅 2026-05-22",
  "      - plain note",
  "      - [ ] #task Grandchild",
  "  - [ ] #task Sibling child",
  "- [ ] #task Root sibling",
  "> - [ ] #task Quoted root",
  ">>  - [ ] #task Quoted sub",
  "```",
  "- [ ] #task Ignored fenced",
  "```",
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

local function has_line(lines, expected)
  for _, line in ipairs(lines) do
    if line == expected then
      return true
    end
  end
  return false
end

local function run(source)
  local tasks = scanner.scan_vault({
    vault_path = root,
    global_filter = "#task",
    today = "2026-05-22",
  })
  local plan = query.parse(source, { today = "2026-05-22" })
  assert(#plan.errors == 0, vim.inspect(plan.errors))
  local filtered = query.filter_tasks(tasks, plan)
  local grouped, order = parser.group_tasks(filtered, {})
  local lines, index_map = display.format_grouped_tasks(grouped, order, {
    layout = plan.layout,
    query_plan = plan,
  })
  return tasks, filtered, lines, index_map
end

local tasks = scanner.scan_vault({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-22",
})
assert(#tasks == 7, vim.inspect(tasks))
assert(tasks[1].list_item ~= nil)
assert(#tasks[1].list_item.children == 2, vim.inspect(tasks[1].list_item.children))
assert(tasks[2].list_item.parent.description == "Planning", tasks[2].list_item.parent.description)

local _, filtered, lines, index_map = run("description includes Parent\nshow tree\nhide backlink")
assert(#filtered == 1, #filtered)
assert(has_line(lines, "1. [ ] #task Parent"), vim.inspect(lines))
assert(has_line(lines, "  - Planning"), vim.inspect(lines))
assert(has_line(lines, "    - [x] Decide who to invite ✅ 2026-05-21"), vim.inspect(lines))
assert(has_line(lines, "    - [ ] #task Child target 📅 2026-05-22"), vim.inspect(lines))
assert(index_map[1] and index_map[1].description == "#task Parent", vim.inspect(index_map))
assert(index_map[2] == nil, vim.inspect(index_map))

_, filtered, lines, index_map = run("description includes Parent\nhide tree\nhide backlink")
assert(#filtered == 1, #filtered)
assert(has_line(lines, "1. [ ] #task Parent"), vim.inspect(lines))
assert(not has_line(lines, "  - Planning"), vim.inspect(lines))
assert(index_map[1] and index_map[1].description == "#task Parent", vim.inspect(index_map))

_, filtered, lines, index_map = run("description includes Child target\nshow tree\nhide backlink")
assert(#filtered == 1, #filtered)
assert(has_line(lines, "    1. [ ] #task Child target 📅 2026-05-22"), vim.inspect(lines))
assert(has_line(lines, "      - plain note"), vim.inspect(lines))
assert(has_line(lines, "      - [ ] #task Grandchild"), vim.inspect(lines))
assert(index_map[1] and index_map[1].description == "#task Child target", vim.inspect(index_map))

_, filtered, lines, index_map = run("not done\nshow tree\nhide backlink")
assert(#filtered == 7, #filtered)
assert(has_line(lines, "1. [ ] #task Parent"), vim.inspect(lines))
assert(has_line(lines, "    2. [ ] #task Child target 📅 2026-05-22"), vim.inspect(lines))
assert(has_line(lines, "      3. [ ] #task Grandchild"), vim.inspect(lines))
assert(has_line(lines, "  7. [ ] #task Quoted sub"), vim.inspect(lines))
assert(index_map[7] and index_map[7].description == "#task Quoted sub", vim.inspect(index_map))

_, filtered, lines, index_map = run("not done\nexclude sub-items\nhide backlink")
assert(#filtered == 3, vim.inspect(filtered))
assert(has_line(lines, "1. [ ] #task Parent"), vim.inspect(lines))
assert(has_line(lines, "2. [ ] #task Root sibling"), vim.inspect(lines))
assert(has_line(lines, "3. [ ] #task Quoted root"), vim.inspect(lines))
assert(not has_line(lines, "4. [ ] #task Quoted sub"), vim.inspect(lines))
assert(index_map[3] and index_map[3].description == "#task Quoted root", vim.inspect(index_map))

local parsed = parser.parse_display_line("    12. [ ] #task Indented [[/tmp/example.md#L9]]")
assert(parsed.index == 12, vim.inspect(parsed))
assert(parsed.display_indentation == "    ", vim.inspect(parsed))
assert(parsed.file_path == "/tmp/example.md", vim.inspect(parsed))
assert(parsed.line_number == 9, vim.inspect(parsed))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase6-3.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
