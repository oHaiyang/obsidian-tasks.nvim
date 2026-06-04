#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local query = require("obsidian-tasks.query")

local tasks = {
  { description = "Work only", text = "Work only", status_symbol = " ", tags = { "#work" } },
  { description = "Home only", text = "Home only", status_symbol = " ", tags = { "#home" } },
  { description = "Both", text = "Both", status_symbol = " ", tags = { "#work", "#home" } },
  { description = "Neither Review", text = "Neither Review", status_symbol = " ", tags = {} },
  { description = "Done Review", text = "Done Review", status_symbol = "x", tags = { "#work" } },
}

local function descriptions(source)
  local plan = query.parse(source)
  assert(#plan.errors == 0, vim.inspect(plan.errors))
  local out = {}
  for _, task in ipairs(query.filter_tasks(tasks, plan)) do
    table.insert(out, task.description)
  end
  table.sort(out)
  return table.concat(out, ",")
end

assert(descriptions("[tag includes #work] XOR [tag includes #home]") == "Done Review,Home only,Work only")
assert(descriptions("{tag includes #work} OR {tag includes #home}") == "Both,Done Review,Home only,Work only")
assert(descriptions('"description includes Review" AND [not done]') == "Neither Review")
assert(descriptions("NOT [done]") == "Both,Home only,Neither Review,Work only")
assert(descriptions("(not done) AND ((tag includes #work) OR (tag includes #home))") == "Both,Home only,Work only")

local plan = query.parse("[tag includes #work XOR [tag includes #home]")
assert(#plan.errors == 1, vim.inspect(plan.errors))
assert(plan.errors[1].message:find("Invalid Boolean expression", 1, true), plan.errors[1].message)
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase8-1.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
