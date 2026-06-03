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

local tasks_file = root .. "/SearchComplete.md"
vim.fn.writefile({
  "# Search Complete",
  "- [ ] #task Alpha prerequisite 🆔 alpha-id",
  "- [ ] #task Beta blocker 🆔 beta-id",
  "- [ ] #task Gamma has no id",
  "- [ ] #task Current depends item 🆔 current-id ⛔ b",
}, tasks_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
  today = "2026-05-22",
  completion = {
    cmp = true,
  },
})

local completion = require("obsidian-tasks.completion")
local task_search = require("obsidian-tasks.task_search")
local edit = require("obsidian-tasks.edit")
local cmp_source = require("obsidian-tasks.completion.cmp").new()

local function has_word(items, word)
  for _, item in ipairs(items) do
    if item.word == word then
      return true, item
    end
  end
  return false, nil
end

local function has_insert(items, word)
  for _, item in ipairs(items) do
    if item.insertText == word then
      return true, item
    end
  end
  return false, nil
end

local candidates = task_search.candidate_tasks({ vault_path = root })
assert(#candidates == 4, vim.inspect(candidates))
assert(task_search.format_candidate(candidates[2]):find("Beta blocker", 1, true), task_search.format_candidate(candidates[2]))

local all_task_items = completion.task_search_items({
  state = { vault_path = root },
  require_id = false,
  no_id_label = "needs id",
})
local saw_no_id = false
for _, item in ipairs(all_task_items) do
  if item.data and item.data.needs_id then
    saw_no_id = true
    assert(item.abbr:find("Gamma has no id", 1, true), vim.inspect(item))
    assert(item.menu == "needs id", vim.inspect(item))
  end
end
assert(saw_no_id, vim.inspect(all_task_items))

vim.cmd("edit " .. vim.fn.fnameescape(tasks_file))
local current_line = vim.api.nvim_buf_get_lines(0, 4, 5, false)[1]
vim.api.nvim_win_set_cursor(0, { 5, #current_line })
local ctx = completion.markdown_context({ buf = 0 })
assert(ctx and ctx.field == "depends_on", vim.inspect(ctx))
assert(ctx.current_task and ctx.current_task.id == "current-id", vim.inspect(ctx.current_task))

local beta_items = completion.suggest({
  context = "markdown",
  field = ctx.field,
  base = "Beta",
  current_task = ctx.current_task,
})
local ok, beta = has_word(beta_items, "beta-id")
assert(ok, vim.inspect(beta_items))
assert(beta.abbr:find("Beta blocker", 1, true), vim.inspect(beta))
assert(beta.abbr:find("SearchComplete.md:3", 1, true), vim.inspect(beta))
assert(beta.data and beta.data.kind == "task", vim.inspect(beta))
assert(beta.data.file_path == tasks_file, vim.inspect(beta.data))
assert(beta.data.line_number == 3, vim.inspect(beta.data))

local current_items = completion.suggest({
  context = "markdown",
  field = "depends_on",
  base = "current",
  current_task = ctx.current_task,
})
assert(not has_word(current_items, "current-id"), vim.inspect(current_items))

assert(completion.apply_completion(beta, ctx, 0))
local updated = vim.api.nvim_buf_get_lines(0, 4, 5, false)[1]
assert(updated:find("⛔ beta-id", 1, true), updated)

vim.api.nvim_win_set_cursor(0, { 5, #updated })
local form_buf = tasks.edit_current_task()
assert(form_buf and vim.api.nvim_buf_is_valid(form_buf))
local form_state = edit.form_state[form_buf]
local form_items = edit.suggest_field("depends_on", "Alpha", form_state)
assert(has_word(form_items, "alpha-id"), vim.inspect(form_items))
local own_items = edit.suggest_field("depends_on", "current", form_state)
assert(not has_word(own_items, "current-id"), vim.inspect(own_items))
pcall(vim.api.nvim_buf_delete, form_buf, { force = true })

local response
cmp_source:complete({
  context = {
    bufnr = 0,
    row = 5,
    filetype = "markdown",
    cursor_line = "- [ ] #task Current depends item 🆔 current-id ⛔ Be",
    cursor_before_line = "- [ ] #task Current depends item 🆔 current-id ⛔ Be",
  },
}, function(result)
  response = result
end)
assert(response, "cmp response missing")
local cmp_ok, cmp_item = has_insert(response.items, "beta-id")
assert(cmp_ok, vim.inspect(response.items))
assert(cmp_item.data and cmp_item.data.kind == "task", vim.inspect(cmp_item))
assert(type(cmp_item.filterText) == "string", vim.inspect(cmp_item))
assert(cmp_item.documentation:find("Beta blocker", 1, true), vim.inspect(cmp_item))
LUA

NVIM_LOG_FILE="${NVIM_LOG_FILE:-/private/tmp/obsidian-tasks-nvim-phase6-6.log}" \
nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
