# Board File Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Lua-configured named query boards with read-only markdown board files whose `tasks` code blocks render as task result sections.

**Architecture:** Add a focused `board.lua` module that reads a markdown file, preserves non-`tasks` markdown, replaces `tasks` fenced blocks with formatted query result sections, and owns board buffer state/keymaps. Keep existing single-query result flow for `run_query()` and `:ObsidianTasksQuery`, while routing `:ObsidianTasks [file]` to board rendering. Extend task mutation code so rendered board task lines write directly back to source tasks and refresh the board.

**Tech Stack:** Lua, Neovim API, existing `obsidian-tasks` query/cache/display/core modules, headless Neovim smoke scripts.

---

## File Structure

- Create `lua/obsidian-tasks/board.lua`: board file resolution, rendering, buffer state, keymaps, refresh, source navigation, file picker.
- Modify `lua/obsidian-tasks/display.lua`: expose reusable result-section formatting and allow result indices to start at a caller-provided offset.
- Modify `lua/obsidian-tasks/core.lua`: detect board buffers and make toggle/status/postpone write through to source files immediately.
- Modify `lua/obsidian-tasks/edit.lua`: refresh an originating board buffer after form-based task edits.
- Modify `lua/obsidian-tasks/init.lua`: stop normalizing `queries/default_query`, keep presets, and route `open()` to the board entry point.
- Modify `lua/obsidian-tasks/panel.lua`: make `:ObsidianTasks [file]` board-based, keep immediate query commands, remove query-name completion and refresh-query command.
- Modify `lua/obsidian-tasks/query_registry.lua`: remove config query sources from any retained registry behavior.
- Create `scripts/smoke_board_renderer.sh`: primary failing and passing test for the new board workflow.
- Modify focused smoke scripts used by this plan's verification: `scripts/smoke_phase2.sh`, `scripts/smoke_phase3.sh`, `scripts/smoke_phase5_4.sh`, `scripts/smoke_phase6_2.sh`, `scripts/smoke_phase7_3.sh`, `scripts/smoke_phase8_3.sh`.

## Task 1: Add Failing Board Renderer Smoke Test

**Files:**
- Create: `scripts/smoke_board_renderer.sh`

- [ ] **Step 1: Create the failing smoke script**

Create `scripts/smoke_board_renderer.sh` with this exact content:

```sh
#!/usr/bin/env sh
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_LUA="$(mktemp)"
trap 'rm -f "$SMOKE_LUA"' EXIT

cat > "$SMOKE_LUA" <<'LUA'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/Projects", "p")
vim.fn.mkdir(root .. "/Other", "p")
local uv = vim.uv or vim.loop
root = uv.fs_realpath(root) or root

local board = root .. "/Projects/Board.md"
local tasks_file = root .. "/Projects/Tasks.md"
local other_file = root .. "/Other/Tasks.md"

vim.fn.writefile({
  "---",
  "TQ_extra_instructions: |-",
  "  folder includes {{query.file.folder}}",
  "TQ_show_task_count: true",
  "---",
  "# Board",
  "",
  "Intro paragraph stays markdown.",
  "",
  "```lua",
  "print('keep me')",
  "```",
  "",
  "```tasks",
  "# name: Project Open",
  "not done",
  "sort by due",
  "```",
  "",
  "Middle paragraph stays markdown.",
  "",
  "```tasks",
  "# name: Broken Query",
  "definitely unsupported",
  "```",
}, board)

vim.fn.writefile({
  "# Project Tasks",
  "- [ ] #task Alpha 📅 2026-06-05",
  "- [ ] #task Beta 📅 2026-06-06",
  "- [x] #task Done 📅 2026-06-04",
}, tasks_file)

vim.fn.writefile({
  "# Other Tasks",
  "- [ ] #task Gamma 📅 2026-06-05",
}, other_file)

local tasks = require("obsidian-tasks")
tasks.setup({
  vault_path = root,
  global_filter = "#task",
})

local function text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function assert_contains(haystack, needle)
  assert(haystack:find(needle, 1, true), haystack .. "\nmissing: " .. needle)
end

local function assert_not_contains(haystack, needle)
  assert(not haystack:find(needle, 1, true), haystack .. "\nunexpected: " .. needle)
end

vim.cmd("ObsidianTasks " .. vim.fn.fnameescape(board))
local buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(buf):find("obsidian%-tasks://board/"), vim.api.nvim_buf_get_name(buf))
assert(vim.bo[buf].filetype == "markdown", vim.bo[buf].filetype)
assert(vim.bo[buf].readonly == true, "board buffer must be readonly")
assert(vim.bo[buf].modifiable == false, "board buffer must be nonmodifiable")
assert(vim.b[buf].obsidian_tasks_board == true, "board marker missing")

local rendered = text()
assert_contains(rendered, "# Board")
assert_contains(rendered, "Intro paragraph stays markdown.")
assert_contains(rendered, "```lua")
assert_contains(rendered, "print('keep me')")
assert_contains(rendered, "## Project Open")
assert_contains(rendered, "Alpha")
assert_contains(rendered, "Beta")
assert_not_contains(rendered, "Gamma")
assert_not_contains(rendered, "sort by due")
assert_not_contains(rendered, "definitely unsupported\n```")
assert_contains(rendered, "## Broken Query")
assert_contains(rendered, "Query errors:")
assert_contains(rendered, "Unsupported query instruction")

local alpha_row
for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  if line:find("Alpha", 1, true) then
    alpha_row = row
    break
  end
end
assert(alpha_row, rendered)
vim.api.nvim_win_set_cursor(0, { alpha_row, 0 })
assert(tasks.toggle_task_at_cursor())

local source_after_toggle = table.concat(vim.fn.readfile(tasks_file), "\n")
assert_contains(source_after_toggle, "- [x] #task Alpha")
assert(vim.bo[buf].readonly == true, "board buffer lost readonly after toggle")
assert(vim.bo[buf].modifiable == false, "board buffer lost nonmodifiable after toggle")
assert_contains(text(), "1. [x]")

vim.cmd("edit " .. vim.fn.fnameescape(board))
vim.cmd("ObsidianTasks")
local current_text = text()
assert(vim.api.nvim_buf_get_name(0):find("obsidian%-tasks://board/"), vim.api.nvim_buf_get_name(0))
assert_contains(current_text, "Middle paragraph stays markdown.")
assert_contains(current_text, "Project Open")

local no_query_file = root .. "/Projects/NoQueries.md"
vim.fn.writefile({
  "# No Queries",
  "",
  "This file has no task query blocks.",
}, no_query_file)
vim.cmd("ObsidianTasks " .. vim.fn.fnameescape(no_query_file))
assert_contains(text(), "No tasks query blocks found")
assert(vim.bo[0].filetype == "markdown", vim.bo[0].filetype)
LUA

nvim --headless -u NONE -i NONE \
  --cmd "set noswapfile" \
  --cmd "set rtp+=$PLUGIN_DIR" \
  -c "luafile $SMOKE_LUA" \
  -c "qa!"
```

- [ ] **Step 2: Make the smoke script executable**

Run:

```bash
chmod +x scripts/smoke_board_renderer.sh
```

Expected: no output.

- [ ] **Step 3: Run the smoke script and verify it fails for the expected reason**

Run:

```bash
sh scripts/smoke_board_renderer.sh
```

Expected: FAIL before implementation. The failure should mention either `unknown query` for the file path or an assertion that the current buffer name does not start with `obsidian-tasks://board/`.

- [ ] **Step 4: Commit the failing smoke test**

Run:

```bash
git add scripts/smoke_board_renderer.sh
git commit -m "test: add board renderer smoke"
```

Expected: commit succeeds with one new smoke script.

## Task 2: Add Reusable Display Section Formatting

**Files:**
- Modify: `lua/obsidian-tasks/display.lua`
- Test: `scripts/smoke_phase5_4.sh`

- [ ] **Step 1: Update `format_grouped_tasks()` to support caller-provided start indices**

In `lua/obsidian-tasks/display.lua`, find `function M.format_grouped_tasks(grouped_tasks, group_order, opts)` and replace the local index initialization:

```lua
local current_index = 1
```

with:

```lua
local current_index = tonumber(opts.start_index or opts.startIndex) or 1
```

Expected: existing callers still start at `1`; board rendering can pass an offset.

- [ ] **Step 2: Add `format_task_result_section()` after `render_task_lines()`**

In `lua/obsidian-tasks/display.lua`, immediately after the existing local `render_task_lines(tasks, opts)` function, add:

```lua
local function max_index(index_map, fallback)
	local max = fallback or 0
	for index, _ in pairs(index_map or {}) do
		if type(index) == "number" and index > max then
			max = index
		end
	end
	return max
end

function M.format_task_result_section(tasks, opts)
	opts = vim.tbl_extend("force", opts or {}, {})
	tasks = tasks or {}
	local visible_tasks = M.filter_tasks_for_toolbar(tasks, opts.toolbar_filter)
	opts.shown_count = opts.shown_count or #visible_tasks
	opts.total_count = opts.total_count or #tasks
	opts.start_index = tonumber(opts.start_index or opts.startIndex) or 1

	local lines = {}
	if trim(opts.section_title) ~= "" then
		table.insert(lines, "## " .. trim(opts.section_title))
	end

	if opts.query_plan and opts.query_plan.explain then
		for _, line in ipairs(require("obsidian-tasks.explain").lines(opts.query_plan, opts)) do
			table.insert(lines, line)
		end
	end

	if M.should_show(opts, "task count", true) then
		local count_line
		if opts.limit and #visible_tasks ~= opts.total_count then
			count_line = string.format("Showing %d of %d tasks", #visible_tasks, opts.total_count)
		else
			count_line = string.format("Showing %d tasks", #visible_tasks)
		end
		table.insert(lines, count_line)
	end

	local display_lines, index_map = render_task_lines(visible_tasks, opts)
	if #display_lines == 0 then
		table.insert(lines, "_No tasks found._")
	else
		for _, line in ipairs(display_lines) do
			table.insert(lines, line)
		end
	end

	return lines, index_map, max_index(index_map, opts.start_index - 1) + 1
end
```

Expected: the helper returns rendered markdown lines, a display-index-to-task map, and the next available display index.

- [ ] **Step 3: Run a layout regression smoke**

Run:

```bash
sh scripts/smoke_phase5_4.sh
```

Expected before Task 6 smoke updates: this script can still fail because it depends on config named queries. If it fails with `unknown query`, continue to Task 6. If it fails with a Lua error from `display.lua`, fix the helper before moving on.

- [ ] **Step 4: Commit the display helper**

Run:

```bash
git add lua/obsidian-tasks/display.lua
git commit -m "feat: expose task result section formatting"
```

Expected: commit succeeds with only `display.lua` changed.

## Task 3: Implement Board Renderer Module

**Files:**
- Create: `lua/obsidian-tasks/board.lua`
- Modify: `lua/obsidian-tasks/core.lua`
- Test: `scripts/smoke_board_renderer.sh`

- [ ] **Step 1: Create `lua/obsidian-tasks/board.lua`**

Create `lua/obsidian-tasks/board.lua` with this implementation:

```lua
local M = {}

M.state = {}

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function realpath(path)
	if not path or path == "" then
		return path
	end
	local uv = vim.uv or vim.loop
	return (uv and uv.fs_realpath(path)) or path
end

local function normalize(path)
	path = realpath(path) or path
	if type(path) == "string" then
		return path:gsub("/+$", "")
	end
	return path
end

local function join_path(root, child)
	if not child or child == "" then
		return root
	end
	if child:sub(1, 1) == "/" then
		return child
	end
	if vim.fs and vim.fs.joinpath then
		return vim.fs.joinpath(root, child)
	end
	return root:gsub("/+$", "") .. "/" .. child
end

local function read_lines(path)
	local file = io.open(path, "r")
	if not file then
		return nil, "Cannot open file: " .. tostring(path)
	end
	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()
	return lines
end

local function is_markdown(path)
	return type(path) == "string" and path:sub(-3) == ".md"
end

local function basename(path)
	return (path or ""):match("([^/]+)$") or path or ""
end

local function slug(value)
	return tostring(value or "board"):gsub("[^%w_%-%./:]+", "_")
end

local function buffer_name(path)
	return "obsidian-tasks://board/" .. slug(path)
end

local function buffer_name_exists(name)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
			return buf
		end
	end
	return nil
end

local function ensure_vault_path()
	local vault_path = normalize(get_config().vault_path)
	if not vault_path or vault_path == "" then
		vim.notify("obsidian-tasks.nvim: vault_path is required to open a board", vim.log.levels.ERROR)
		return nil
	end
	return vault_path
end

local function inside_vault(path, vault_path)
	path = normalize(path)
	vault_path = normalize(vault_path)
	if not path or not vault_path then
		return false
	end
	return path == vault_path or path:sub(1, #vault_path + 1) == vault_path .. "/"
end

local function resolve_path(path)
	local vault_path = ensure_vault_path()
	if not vault_path then
		return nil
	end

	if not path or path == "" then
		local current = vim.api.nvim_buf_get_name(0)
		if is_markdown(current) and inside_vault(current, vault_path) then
			return normalize(current)
		end
		return nil, "pick"
	end

	local resolved = normalize(path)
	if not inside_vault(resolved, vault_path) then
		resolved = normalize(join_path(vault_path, path))
	end
	if not inside_vault(resolved, vault_path) then
		vim.notify("obsidian-tasks.nvim: board file must be inside vault_path: " .. tostring(path), vim.log.levels.ERROR)
		return nil
	end
	if not is_markdown(resolved) then
		vim.notify("obsidian-tasks.nvim: board file must be a markdown file: " .. tostring(path), vim.log.levels.ERROR)
		return nil
	end
	return resolved
end

local function markdown_files_with_queries(vault_path)
	local pattern = vim.fs and vim.fs.joinpath and vim.fs.joinpath(vault_path, "**", "*.md")
		or (vault_path:gsub("/$", "") .. "/**/*.md")
	local files = vim.fn.glob(pattern, false, true)
	table.sort(files)
	local result = {}
	for _, path in ipairs(files) do
		if #require("obsidian-tasks.query_block").scan_file(path) > 0 then
			table.insert(result, path)
		end
	end
	return result
end

local function section_title(source)
	if source.name and source.name ~= "" and not source.unnamed then
		return source.name
	end
	return string.format("Tasks query at %s#L%d", basename(source.source_path), source.source_line or 1)
end

local function apply_limit(tasks, limit)
	if not limit or limit <= 0 or #tasks <= limit then
		return tasks
	end
	local limited = {}
	for index = 1, limit do
		table.insert(limited, tasks[index])
	end
	return limited
end

local function execute_source(source, opts)
	opts = opts or {}
	local config = get_config()
	local query = require("obsidian-tasks.query")
	local display = require("obsidian-tasks.display")
	local sorter = require("obsidian-tasks.sort")
	local cache = require("obsidian-tasks.cache")

	local query_opts = {
		today = opts.today,
		config = config,
		enable_lua_filters = config.enable_lua_filters or config.enableLuaFilters,
		query_source = source,
		query_file_path = source.source_path,
		source_path = source.source_path,
	}
	local composition = query.compose(source.query, query_opts)
	local plan = query.parse(composition.source, query_opts)
	plan.composition = composition
	plan.original_query = source.query

	if #plan.errors > 0 then
		local lines = { "## " .. section_title(source), "Query errors:" }
		for _, err in ipairs(plan.errors) do
			table.insert(lines, string.format("- line %s: %s", err.line or "?", err.message or "Unknown query error"))
			if err.instruction and err.instruction ~= "" then
				table.insert(lines, "  instruction: " .. err.instruction)
			end
		end
		return lines, {}, opts.start_index or 1, plan
	end

	local tasks = cache.tasks({
		vault_path = config.vault_path,
		global_filter = config.global_filter,
		remove_global_filter = config.remove_global_filter,
		today = opts.today,
		use_cache = opts.use_cache or opts.useCache,
	})
	local filtered = query.filter_tasks(tasks, plan)
	if #plan.sorts > 0 then
		filtered = sorter.apply(filtered, plan.sorts)
	end

	local total_count = #filtered
	filtered = apply_limit(filtered, plan.limit)

	return display.format_task_result_section(filtered, {
		section_title = section_title(source),
		query_plan = plan,
		layout = plan.layout,
		group_by = plan.group_by,
		hierarchical_headings = config.display and config.display.hierarchical_headings or false,
		total_count = total_count,
		limit = plan.limit,
		start_index = opts.start_index or 1,
	})
end

local function merge_index_map(target, source)
	for index, task in pairs(source or {}) do
		target[index] = task
	end
end

local function build_board_lines(path, source_lines)
	local query_block = require("obsidian-tasks.query_block")
	local sources = query_block.scan_lines(source_lines, path)
	local lines = {}
	local sections = {}
	local index_map = {}
	local next_source_line = 1
	local next_task_index = 1

	for _, source in ipairs(sources) do
		for line_number = next_source_line, source.source_line - 1 do
			table.insert(lines, source_lines[line_number] or "")
		end

		local render_start = #lines + 1
		local section_lines, section_index_map, next_index = execute_source(source, {
			start_index = next_task_index,
		})
		for _, line in ipairs(section_lines) do
			table.insert(lines, line)
		end
		merge_index_map(index_map, section_index_map)
		next_task_index = next_index
		table.insert(sections, {
			source = source,
			render_start = render_start,
			render_end = #lines,
		})

		next_source_line = source.end_line + 1
	end

	for line_number = next_source_line, #source_lines do
		table.insert(lines, source_lines[line_number] or "")
	end

	if #sources == 0 then
		table.insert(lines, 1, "> No tasks query blocks found")
		table.insert(lines, 2, "")
	end

	return lines, sections, index_map
end

local function configure_buffer(buf, path)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.b[buf].obsidian_tasks_board = true
	vim.b[buf].obsidian_tasks_board_source = path
end

local function set_buffer_lines(buf, lines)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_set_option_value("readonly", false, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modified", false, { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

local function state_for(buf)
	return M.state[buf or vim.api.nvim_get_current_buf()]
end

function M.is_board_buffer(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].obsidian_tasks_board == true
end

function M.refresh(opts)
	opts = opts or {}
	local buf = opts.buffer or opts.buf or vim.api.nvim_get_current_buf()
	local state = state_for(buf)
	if not state then
		vim.notify("obsidian-tasks.nvim: current buffer is not a board", vim.log.levels.ERROR)
		return false
	end

	local win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(win)
	local source_lines, err = read_lines(state.source_path)
	if not source_lines then
		vim.notify(err, vim.log.levels.ERROR)
		return false
	end
	local lines, sections, index_map = build_board_lines(state.source_path, source_lines)
	set_buffer_lines(buf, lines)
	M.state[buf] = {
		source_path = state.source_path,
		sections = sections,
	}
	require("obsidian-tasks.core").task_index_map[buf] = index_map
	require("obsidian-tasks.core").buffer_tasks[buf] = nil

	if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_buf() == buf then
		local row = math.min(cursor[1], vim.api.nvim_buf_line_count(buf))
		pcall(vim.api.nvim_win_set_cursor, win, { row, cursor[2] })
	end
	return true
end

local function setup_keymaps(buf)
	vim.keymap.set("n", "q", function()
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end, { buffer = buf, noremap = true, silent = true, desc = "Close tasks board" })

	vim.keymap.set("n", "<c-r>", function()
		M.refresh({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Refresh tasks board" })

	vim.keymap.set("n", "gq", function()
		M.go_to_query_source({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Go to query source" })

	vim.keymap.set({ "n" }, "gd", function()
		M.go_to_task_source({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Go to task source" })
	vim.keymap.set({ "n" }, "gf", function()
		M.go_to_task_source({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Go to task source" })

	vim.keymap.set({ "n" }, "<space>", require("obsidian-tasks").toggle_task_at_cursor, {
		buffer = buf,
		noremap = true,
		silent = true,
		desc = "Toggle task status",
	})
	vim.keymap.set("n", "s", function()
		local entries = require("obsidian-tasks.status").registry(require("obsidian-tasks").config or {})
		vim.ui.select(entries, {
			prompt = "Task status",
			format_item = function(entry)
				return string.format("[%s] %s (%s)", entry.symbol, entry.name, entry.type)
			end,
		}, function(entry)
			if entry then
				require("obsidian-tasks").change_task_status_at_cursor(entry.symbol)
			end
		end)
	end, { buffer = buf, noremap = true, silent = true, desc = "Change task status" })
	vim.keymap.set("n", "p", function()
		require("obsidian-tasks").postpone_task_at_cursor()
	end, { buffer = buf, noremap = true, silent = true, desc = "Postpone task" })
	vim.keymap.set("n", "e", function()
		require("obsidian-tasks").edit_current_task()
	end, { buffer = buf, noremap = true, silent = true, desc = "Edit task" })
end

function M.open_path(path)
	local source_lines, err = read_lines(path)
	if not source_lines then
		vim.notify(err, vim.log.levels.ERROR)
		return nil
	end
	local name = buffer_name(path)
	local buf = buffer_name_exists(name)
	if not buf then
		buf = vim.api.nvim_create_buf(true, false)
		pcall(vim.api.nvim_buf_set_name, buf, name)
		configure_buffer(buf, path)
		setup_keymaps(buf)
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = buf,
			once = true,
			callback = function()
				M.state[buf] = nil
				require("obsidian-tasks.core").task_index_map[buf] = nil
			end,
		})
	end

	local lines, sections, index_map = build_board_lines(path, source_lines)
	set_buffer_lines(buf, lines)
	M.state[buf] = {
		source_path = path,
		sections = sections,
	}
	require("obsidian-tasks.core").task_index_map[buf] = index_map
	require("obsidian-tasks.core").buffer_tasks[buf] = nil
	vim.api.nvim_set_current_buf(buf)
	return buf
end

function M.open(opts)
	opts = opts or {}
	if type(opts) == "string" then
		opts = { path = opts }
	end
	local path, mode = resolve_path(opts.path or opts.file or opts.file_path or opts.filePath or opts.name)
	if mode == "pick" then
		local vault_path = ensure_vault_path()
		if not vault_path then
			return nil
		end
		local files = markdown_files_with_queries(vault_path)
		if #files == 0 then
			vim.notify("obsidian-tasks.nvim: no markdown files with tasks query blocks found", vim.log.levels.WARN)
			return nil
		end
		vim.ui.select(files, {
			prompt = "Obsidian Tasks board",
			format_item = function(item)
				return item:gsub("^" .. vim.pesc(vault_path .. "/"), "")
			end,
		}, function(choice)
			if choice then
				M.open_path(choice)
			end
		end)
		return nil
	end
	if not path then
		return nil
	end
	return M.open_path(path)
end

local function section_at_row(state, row)
	for _, section in ipairs(state.sections or {}) do
		if row >= section.render_start and row <= section.render_end then
			return section
		end
	end
	return nil
end

function M.go_to_query_source(opts)
	opts = opts or {}
	local buf = opts.buffer or opts.buf or vim.api.nvim_get_current_buf()
	local state = state_for(buf)
	if not state then
		vim.notify("obsidian-tasks.nvim: current buffer is not a board", vim.log.levels.WARN)
		return false
	end
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local section = section_at_row(state, row)
	if not section or not section.source then
		vim.notify("obsidian-tasks.nvim: cursor is not in a rendered query section", vim.log.levels.WARN)
		return false
	end
	vim.cmd("edit +" .. section.source.source_line .. " " .. vim.fn.fnameescape(section.source.source_path))
	return true
end

local function task_at_cursor(buf)
	local line = vim.api.nvim_get_current_line()
	local index = tonumber(line:match("^%s*(%d+)%. "))
	return index and (require("obsidian-tasks.core").task_index_map[buf] or {})[index] or nil
end

function M.go_to_task_source(opts)
	opts = opts or {}
	local buf = opts.buffer or opts.buf or vim.api.nvim_get_current_buf()
	local task = task_at_cursor(buf)
	if not task then
		vim.notify("obsidian-tasks.nvim: cursor is not on a rendered task", vim.log.levels.WARN)
		return false
	end
	local located, locate_err = require("obsidian-tasks.source").locate_in_file(task)
	if not located then
		vim.notify(locate_err or "Task source line changed; refresh the board", vim.log.levels.WARN)
		return false
	end
	vim.cmd("edit +" .. located .. " " .. vim.fn.fnameescape(task.file_path))
	return true
end

function M.refresh_after_mutation(buf)
	if M.is_board_buffer(buf) then
		return M.refresh({ buffer = buf })
	end
	return false
end

return M
```

- [ ] **Step 2: Add a board buffer marker helper in `core.lua`**

In `lua/obsidian-tasks/core.lua`, after `local function get_config()`, add:

```lua
local function is_board_buffer(buf)
	local ok, board = pcall(require, "obsidian-tasks.board")
	return ok and board.is_board_buffer(buf)
end

local function refresh_board_after_mutation(buf)
	local ok, board = pcall(require, "obsidian-tasks.board")
	if ok and board.is_board_buffer(buf) then
		return board.refresh_after_mutation(buf)
	end
	return false
end
```

Expected: later task-mutation changes can detect board buffers without creating hard startup dependencies.

- [ ] **Step 3: Run the board smoke and verify the next expected failure**

Run:

```bash
sh scripts/smoke_board_renderer.sh
```

Expected at this point: FAIL because `:ObsidianTasks` still routes through `panel.open_query()` and does not call `board.open()`.

- [ ] **Step 4: Commit the board module**

Run:

```bash
git add lua/obsidian-tasks/board.lua lua/obsidian-tasks/core.lua
git commit -m "feat: add read-only board renderer"
```

Expected: commit succeeds with the new board module and core helpers.

## Task 4: Route Main API And Commands To Board Files

**Files:**
- Modify: `lua/obsidian-tasks/init.lua`
- Modify: `lua/obsidian-tasks/panel.lua`
- Modify: `lua/obsidian-tasks/display.lua`
- Test: `scripts/smoke_board_renderer.sh`

- [ ] **Step 1: Stop normalizing named board queries in `init.lua`**

In `lua/obsidian-tasks/init.lua`, remove these lines from `M.setup(config)`:

```lua
config.queries = config.queries or {}
config.default_query = config.default_query or config.defaultQuery
```

Keep this line unchanged:

```lua
config.presets = config.presets or config.query_presets or config.queryPresets or {}
```

- [ ] **Step 2: Route `M.open()` to `board.open()`**

In `lua/obsidian-tasks/init.lua`, replace:

```lua
function M.open(opts)
	return require("obsidian-tasks.panel").open(opts)
end
```

with:

```lua
function M.open(opts)
	return require("obsidian-tasks.board").open(opts)
end
```

- [ ] **Step 3: Replace `panel.open()` and `panel.open_query()` semantics**

In `lua/obsidian-tasks/panel.lua`, replace the existing `M.open()` and `M.open_query()` functions with:

```lua
function M.open(opts)
	return require("obsidian-tasks.board").open(opts)
end

function M.open_query(name, opts)
	vim.notify(
		"obsidian-tasks.nvim: named Lua-config queries are no longer supported. Move this query into a vault ```tasks code block and open the markdown board file.",
		vim.log.levels.ERROR
	)
	return nil
end
```

Expected: `require("obsidian-tasks").open_query("name")` fails with a migration message instead of silently consulting config queries.

- [ ] **Step 4: Replace the `:ObsidianTasks` command**

In `lua/obsidian-tasks/panel.lua`, replace the existing `ObsidianTasks` command definition:

```lua
vim.api.nvim_create_user_command("ObsidianTasks", function(command)
	M.open_query(command.args ~= "" and command.args or nil, {
		pinned = command.bang,
	})
end, {
	nargs = "?",
	bang = true,
	force = true,
	complete = function()
		return M.complete_query_names()
	end,
})
```

with:

```lua
vim.api.nvim_create_user_command("ObsidianTasks", function(command)
	require("obsidian-tasks.board").open({
		path = command.args ~= "" and command.args or nil,
	})
end, {
	nargs = "?",
	bang = true,
	force = true,
	complete = "file",
})
```

Expected: the bang is accepted for backward command compatibility and has no board-specific behavior.

- [ ] **Step 5: Remove the refresh-query command registration**

In `lua/obsidian-tasks/panel.lua`, delete this command block:

```lua
vim.api.nvim_create_user_command("ObsidianTasksRefreshQueries", function()
	M.refresh_queries()
end, {
	force = true,
})
```

Expected: `:ObsidianTasksRefreshQueries` no longer exists after setup.

- [ ] **Step 6: Make `:ObsidianTasksRefresh` board-aware**

In `lua/obsidian-tasks/panel.lua`, replace:

```lua
vim.api.nvim_create_user_command("ObsidianTasksRefresh", function()
	require("obsidian-tasks.display").refresh_tasks_view()
end, {
	force = true,
})
```

with:

```lua
vim.api.nvim_create_user_command("ObsidianTasksRefresh", function()
	local board = require("obsidian-tasks.board")
	if board.is_board_buffer(0) then
		board.refresh({ buffer = 0 })
	else
		require("obsidian-tasks.display").refresh_tasks_view()
	end
end, {
	force = true,
})
```

- [ ] **Step 7: Remove query cycling keymaps from result buffers**

In `lua/obsidian-tasks/display.lua`, remove this line from `build_header_lines(opts)`:

```lua
"o queries  [q previous query  ]q next query  gq query source",
```

Then remove the `o`, `]q`, and `[q` keymap blocks from `M.setup_editable_buffer()`. Keep the existing `gq` mapping.

Expected: old single-query result buffers no longer expose query registry navigation.

- [ ] **Step 8: Run the board smoke and verify mutation is now the only expected failure**

Run:

```bash
sh scripts/smoke_board_renderer.sh
```

Expected: board rendering assertions pass until `<space>`/`toggle_task_at_cursor()` attempts to edit a readonly board buffer. The failure should mention `modifiable` or show that the source task was not toggled.

- [ ] **Step 9: Commit command routing**

Run:

```bash
git add lua/obsidian-tasks/init.lua lua/obsidian-tasks/panel.lua lua/obsidian-tasks/display.lua
git commit -m "feat: route tasks command to board files"
```

Expected: commit succeeds.

## Task 5: Make Board Task Mutations Write Through And Refresh

**Files:**
- Modify: `lua/obsidian-tasks/core.lua`
- Modify: `lua/obsidian-tasks/edit.lua`
- Test: `scripts/smoke_board_renderer.sh`

- [ ] **Step 1: Add a source-write helper in `core.lua`**

In `lua/obsidian-tasks/core.lua`, after `update_display_status_line()`, add:

```lua
local function apply_display_status_to_source(buf, parsed, next_symbol)
	local index_map = M.task_index_map[buf] or {}
	local original_task = parsed.index and index_map[parsed.index] or nil
	if not original_task then
		vim.notify("No source task for display line", vim.log.levels.ERROR)
		return false
	end
	local ok = M.apply_task_changes(original_task, {
		status_symbol = next_symbol,
		status = status_model.status_text(next_symbol),
	})
	if ok then
		refresh_board_after_mutation(buf)
	end
	return ok
end
```

- [ ] **Step 2: Make toggle write through in board buffers**

In `M.toggle_task_at_cursor()` in `lua/obsidian-tasks/core.lua`, replace:

```lua
if parsed then
	local next_symbol = status_model.next_symbol(parsed.status_symbol, get_config())
	return update_display_status_line(buf, row, parsed, next_symbol)
end
```

with:

```lua
if parsed then
	local next_symbol = status_model.next_symbol(parsed.status_symbol, get_config())
	if is_board_buffer(buf) then
		return apply_display_status_to_source(buf, parsed, next_symbol)
	end
	return update_display_status_line(buf, row, parsed, next_symbol)
end
```

- [ ] **Step 3: Make explicit status changes write through in board buffers**

In `M.change_task_status_at_cursor(status)` in `lua/obsidian-tasks/core.lua`, replace:

```lua
if parsed then
	return update_display_status_line(buf, row, parsed, next_symbol)
end
```

with:

```lua
if parsed then
	if is_board_buffer(buf) then
		return apply_display_status_to_source(buf, parsed, next_symbol)
	end
	return update_display_status_line(buf, row, parsed, next_symbol)
end
```

- [ ] **Step 4: Make postpone refresh board buffers**

In `M.postpone_task_at_cursor(expr)` in `lua/obsidian-tasks/core.lua`, replace:

```lua
if M.apply_postpone_changes(original_task, expr) then
	require("obsidian-tasks.display").refresh_tasks_view()
	return true
end
```

with:

```lua
if M.apply_postpone_changes(original_task, expr) then
	if is_board_buffer(buf) then
		refresh_board_after_mutation(buf)
	else
		require("obsidian-tasks.display").refresh_tasks_view()
	end
	return true
end
```

- [ ] **Step 5: Track originating board buffer for task edit forms**

In `lua/obsidian-tasks/edit.lua`, inside `M.edit_current_task()`, add a return buffer field to the display-task `state` table.

```lua
return_buf = require("obsidian-tasks.board").is_board_buffer(buf) and buf or nil,
```

The resulting state table should include:

```lua
state = {
	mode = "edit",
	file_path = task.file_path,
	line_number = task.line_number,
	indentation = task.indentation,
	list_marker = task.list_marker,
	source_task = task,
	today = get_config().today,
	vault_path = get_config().vault_path,
	task_format = task.task_format or task.taskFormat or task_model.task_format(),
	return_buf = require("obsidian-tasks.board").is_board_buffer(buf) and buf or nil,
}
```

- [ ] **Step 6: Refresh originating board after saving an edit form**

In `lua/obsidian-tasks/edit.lua`, in `M.save_form(buf)`, after:

```lua
vim.notify(state.mode == "create" and "Task created" or "Task updated", vim.log.levels.INFO)
```

add:

```lua
if state.return_buf and vim.api.nvim_buf_is_valid(state.return_buf) then
	pcall(require("obsidian-tasks.board").refresh_after_mutation, state.return_buf)
end
```

- [ ] **Step 7: Run the board smoke and verify it passes**

Run:

```bash
sh scripts/smoke_board_renderer.sh
```

Expected: PASS.

- [ ] **Step 8: Commit board mutation support**

Run:

```bash
git add lua/obsidian-tasks/core.lua lua/obsidian-tasks/edit.lua
git commit -m "feat: write board task actions to source"
```

Expected: commit succeeds.

## Task 6: Remove Config Query Registry Behavior And Update Focused Smoke Scripts

**Files:**
- Modify: `lua/obsidian-tasks/query_registry.lua`
- Modify: `scripts/smoke_phase2.sh`
- Modify: `scripts/smoke_phase3.sh`
- Modify: `scripts/smoke_phase5_4.sh`
- Modify: `scripts/smoke_phase6_2.sh`
- Modify: `scripts/smoke_phase7_3.sh`
- Modify: `scripts/smoke_phase8_3.sh`
- Test: all modified smoke scripts

- [ ] **Step 1: Remove config sources from `query_registry.lua`**

In `lua/obsidian-tasks/query_registry.lua`, delete the `normalize_config_source()` and `config_sources()` local functions.

Then in `M.get_sources(opts)`, delete this loop:

```lua
for _, source in ipairs(config_sources()) do
	table.insert(sources, decorate(source))
end
```

Then in the sort order table inside `M.get_sources(opts)`, replace:

```lua
local order = {
	config = 1,
	block = 2,
	recent = 3,
}
```

with:

```lua
local order = {
	block = 1,
	recent = 2,
}
```

Expected: any retained registry only sees vault block sources and recent ad hoc sources.

- [ ] **Step 2: Update `scripts/smoke_phase2.sh` to test migration and immediate query**

In `scripts/smoke_phase2.sh`, remove these setup fields:

```lua
default_query = "due_soon",
queries = {
  due_soon = [[
not done
due on or before 2026-05-20
sort by due
group by filename
limit 2
]],
  inbox = [[
not done
sort by due
]],
},
```

Replace:

```lua
tasks.open()
```

with:

```lua
tasks.run_query([[
not done
due on or before 2026-05-20
sort by due
group by filename
limit 2
]])
```

Replace:

```lua
assert(text:find("Tasks: due_soon", 1, true), text)
```

with:

```lua
assert(text:find("Tasks: manual", 1, true), text)
```

Replace:

```lua
vim.cmd("ObsidianTasks! inbox")
```

with:

```lua
tasks.run_query([[
not done
sort by due
]])
```

After the immediate `inbox` query assertions, insert:

```lua
local before_open_query = vim.api.nvim_get_current_buf()
tasks.open_query("inbox")
assert(vim.api.nvim_get_current_buf() == before_open_query, "open_query should not open named config queries")
```

Expected: phase 2 still verifies commands exist and immediate queries work, while named config queries are rejected.

- [ ] **Step 3: Update `scripts/smoke_phase3.sh` to use block-backed board behavior**

In `scripts/smoke_phase3.sh`, remove the setup fields:

```lua
default_query = "due-soon",
queries = {
  inbox = [[
not done
sort by due
]],
},
```

Replace:

```lua
assert(seen["config:inbox"], vim.inspect(sources))
```

with:

```lua
assert(not seen["config:inbox"], vim.inspect(sources))
```

Replace:

```lua
tasks.open()
```

with:

```lua
tasks.open({ path = dashboard })
```

Replace assertions expecting `Tasks: Due soon` with assertions expecting board content:

```lua
assert(text:find("# Dashboard", 1, true), text)
assert(text:find("## Due soon", 1, true), text)
```

Delete this command-existence assertion:

```lua
assert(vim.api.nvim_get_commands({}).ObsidianTasksRefreshQueries)
```

Expected: phase 3 verifies query block scanning, board rendering, run-block, and preview without config queries.

- [ ] **Step 4: Update `scripts/smoke_phase5_4.sh` layout result queries**

In `scripts/smoke_phase5_4.sh`, remove this setup table:

```lua
queries = {
  compact = [[
description includes Alpha
hide task count
hide backlink
hide priority
hide tags
hide due date
hide id
]],
  visible = [[
description includes Beta
show task count
show backlink
show priority
show tags
show due date
show id
]],
},
```

Replace:

```lua
tasks.open_query("compact")
```

with:

```lua
tasks.run_query([[
description includes Alpha
hide task count
hide backlink
hide priority
hide tags
hide due date
hide id
]])
```

Replace:

```lua
tasks.open_query("visible")
```

with:

```lua
tasks.run_query([[
description includes Beta
show task count
show backlink
show priority
show tags
show due date
show id
]])
```

- [ ] **Step 5: Update `scripts/smoke_phase6_2.sh` urgency result queries**

In `scripts/smoke_phase6_2.sh`, remove this setup table:

```lua
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
```

Replace:

```lua
tasks.open_query("urgency_sorted")
```

with:

```lua
tasks.run_query([[
not done
sort by urgency
show urgency
]])
```

Replace:

```lua
tasks.open_query("urgency_reverse")
```

with:

```lua
tasks.run_query([[
not done
sort by urgency reverse
show urgency
]])
```

Replace:

```lua
tasks.open_query("urgency_hidden")
```

with:

```lua
tasks.run_query([[
not done
sort by urgency
hide urgency
]])
```

Replace:

```lua
tasks.open_query("urgency_short")
```

with:

```lua
tasks.run_query([[
not done
sort by urgency
short mode
show urgency
]])
```

- [ ] **Step 6: Update `scripts/smoke_phase7_3.sh` refresh result queries**

In `scripts/smoke_phase7_3.sh`, remove this setup table:

```lua
queries = {
  all = [[
not done
sort by description
]],
  beta = [[
description includes Beta
sort by description
]],
},
```

Replace:

```lua
tasks.open_query("all")
```

with:

```lua
tasks.run_query([[
not done
sort by description
]])
```

Replace:

```lua
tasks.open_query("beta", { pinned = true })
```

with:

```lua
tasks.run_query([[
description includes Beta
sort by description
]], { pinned = true })
```

Expected: the pinned single-query result path remains covered through `run_query()`.

- [ ] **Step 7: Update `scripts/smoke_phase8_3.sh` explain result queries**

In `scripts/smoke_phase8_3.sh`, remove this setup table:

```lua
queries = {
  explain = [[
explain
not done
tag includes #work
sort by due
]],
  bad = [[
explain
definitely unsupported
]],
},
```

Replace:

```lua
tasks.open_query("explain")
```

with:

```lua
tasks.run_query([[
explain
not done
tag includes #work
sort by due
]])
```

Replace:

```lua
tasks.open_query("bad")
```

with:

```lua
tasks.run_query([[
explain
definitely unsupported
]])
```

- [ ] **Step 8: Run modified smoke scripts**

Run:

```bash
sh scripts/smoke_phase2.sh
sh scripts/smoke_phase3.sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase6_2.sh
sh scripts/smoke_phase7_3.sh
sh scripts/smoke_phase8_3.sh
```

Expected: all modified scripts PASS.

- [ ] **Step 9: Commit registry cleanup and smoke updates**

Run:

```bash
git add lua/obsidian-tasks/query_registry.lua scripts/smoke_phase2.sh scripts/smoke_phase3.sh scripts/smoke_phase5_4.sh scripts/smoke_phase6_2.sh scripts/smoke_phase7_3.sh scripts/smoke_phase8_3.sh
git commit -m "test: remove named query smoke dependencies"
```

Expected: commit succeeds.

## Task 7: Final Verification And Documentation Check

**Files:**
- Modify only if verification finds a concrete defect.
- Test: primary and regression smoke scripts.

- [ ] **Step 1: Run primary board smoke**

Run:

```bash
sh scripts/smoke_board_renderer.sh
```

Expected: PASS.

- [ ] **Step 2: Run focused regression smoke scripts**

Run:

```bash
sh scripts/smoke_phase3.sh
sh scripts/smoke_phase5_3.sh
sh scripts/smoke_phase5_4.sh
sh scripts/smoke_phase7_3.sh
sh scripts/smoke_phase8_3.sh
```

Expected: PASS.

- [ ] **Step 3: Run broad smoke scripts that were not edited**

Run:

```bash
sh scripts/smoke_phase5_10.sh
sh scripts/smoke_phase6_8.sh
sh scripts/smoke_phase7_4.sh
```

Expected: PASS.

- [ ] **Step 4: Verify unsupported config queries have no command path**

Run this headless check:

```bash
nvim --headless -u NONE -i NONE \
  --cmd "set rtp+=$(pwd)" \
  -c "lua require('obsidian-tasks').setup({ vault_path = vim.fn.tempname(), queries = { old = 'not done' }, default_query = 'old' })" \
  -c "lua require('obsidian-tasks').open_query('old')" \
  -c "lua assert(vim.api.nvim_buf_get_name(0) == '', vim.api.nvim_buf_get_name(0))" \
  -c "qa!"
```

Expected: PASS, with a notification explaining that named Lua-config queries are no longer supported.

- [ ] **Step 5: Inspect git status**

Run:

```bash
git status --short
```

Expected: empty output.

- [ ] **Step 6: Commit verification fixes if any were needed**

If Step 1 through Step 4 required code or test fixes, run:

```bash
git add lua scripts
git commit -m "fix: stabilize board renderer workflow"
```

Expected: commit succeeds only when verification changes exist. If no fixes were needed, do not create an empty commit.
