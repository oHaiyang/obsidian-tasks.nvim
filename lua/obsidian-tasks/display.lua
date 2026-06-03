local M = {}

-- Help information
M.TASK_VIEW_HELP_LINES = {
	"-- Tasks List (q:close, <c-s>:save changes, <c-r>:refresh), J/K move between task --",
	"-- Change `[ ]` to `[x]` to mark tasks as done --",
	"",
}

local core = require("obsidian-tasks.core")
local parser = require("obsidian-tasks.parser")
local task_model = require("obsidian-tasks.task")
local urgency = require("obsidian-tasks.urgency")

-- Store the last used options for refresh functionality
M.last_finder_opts = {}
M.buffer_finder_opts = {}
M.buffer_display_opts = {}
M.buffer_header_line_count = {}

local DATE_DISPLAY = {
	{ field = "created date", key = "created_date", symbol = "➕" },
	{ field = "start date", key = "start_date", symbol = "🛫" },
	{ field = "scheduled date", key = "scheduled_date", symbol = "⏳" },
	{ field = "due date", key = "due_date", symbol = "📅" },
	{ field = "cancelled date", key = "cancelled_date", symbol = "❌" },
	{ field = "done date", key = "done_date", symbol = "✅" },
}

local FIELD_ALIASES = {
	backlinks = "backlink",
	priority = "priority",
	tags = "tags",
	id = "id",
	["depends on"] = "depends on",
	depends_on = "depends on",
	recurrence = "recurrence rule",
	["recurrence rule"] = "recurrence rule",
	["on completion"] = "on completion",
	["task count"] = "task count",
	toolbar = "toolbar",
	tree = "tree",
	urgency = "urgency",
	["edit button"] = "edit button",
	["postpone button"] = "postpone button",
	["created date"] = "created date",
	created = "created date",
	["start date"] = "start date",
	start = "start date",
	starts = "start date",
	["scheduled date"] = "scheduled date",
	scheduled = "scheduled date",
	["due date"] = "due date",
	due = "due date",
	["cancelled date"] = "cancelled date",
	cancelled = "cancelled date",
	canceled = "cancelled date",
	["done date"] = "done date",
	done = "done date",
}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function pattern_escape(value)
	return (value or ""):gsub("([^%w])", "%%%1")
end

local function layout(opts)
	opts = opts or {}
	return opts.layout or (opts.query_plan and opts.query_plan.layout) or {}
end

local function normalize_field(field)
	field = trim(field):lower():gsub("%s+", " ")
	return FIELD_ALIASES[field] or field
end

function M.should_show(opts, field, default)
	local show = layout(opts).show or {}
	local value = show[normalize_field(field)]
	if value == nil then
		return default
	end
	return value == true
end

local function short_mode(opts)
	return layout(opts).short_mode == true
end

local function has_layout_directives(opts)
	local current_layout = layout(opts)
	return current_layout.short_mode ~= nil or (current_layout.show and next(current_layout.show) ~= nil)
end

local function tree_enabled(opts)
	return M.should_show(opts, "tree", false)
end

local function toolbar_visible(opts)
	return M.should_show(opts, "toolbar", true)
end

local function append_part(parts, value)
	value = trim(value)
	if value ~= "" then
		table.insert(parts, value)
	end
end

local function metadata_part(symbol, value, opts)
	if trim(value) == "" then
		return ""
	end
	if short_mode(opts) then
		return symbol
	end
	return symbol .. " " .. trim(value)
end

local function description_without_tags(task)
	local description = task.description or task.text or task.body or ""
	for _, tag in ipairs(task.tags or {}) do
		description = description:gsub("%s*" .. pattern_escape(tag), "")
	end
	description = description:gsub("^#[%w_/%-]+%s*", "")
	description = description:gsub("%s+#[%w_/%-]+", "")
	return trim(description)
end

local function buffer_name_exists(name)
	if not name or name == "" then
		return nil
	end

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
			return buf
		end
	end
	return nil
end

local function create_or_reuse_buffer(opts, listed)
	opts = opts or {}
	if type(opts.reuse_buffer) == "number" and vim.api.nvim_buf_is_valid(opts.reuse_buffer) then
		return opts.reuse_buffer
	end

	if opts.reuse_buffer and opts.buffer_name then
		local existing = buffer_name_exists(opts.buffer_name)
		if existing then
			return existing
		end
	end

	local buf = vim.api.nvim_create_buf(listed, false)
	if opts.buffer_name and opts.buffer_name ~= "" then
		pcall(vim.api.nvim_buf_set_name, buf, opts.buffer_name)
	end
	return buf
end

local function build_header_lines(opts)
	opts = opts or {}
	local query_name = opts.query_name or "Tasks List"
	local shown = opts.shown_count
	local total = opts.total_count
	local title = "Tasks: " .. query_name

	if shown ~= nil and total ~= nil then
		if M.should_show(opts, "task count", true) == false then
			-- Count explicitly hidden by query layout.
		elseif opts.limit and shown ~= total then
			title = string.format("%s                          Showing %d of %d tasks", title, shown, total)
		else
			title = string.format("%s                          Showing %d tasks", title, shown)
		end
	end

	local source = "Source: "
	if opts.query_source and opts.query_source.source_label then
		source = source .. opts.query_source.source_type .. " " .. opts.query_source.source_label
	elseif opts.query_source and opts.query_source.source_path and opts.query_source.source_line then
		local filename = opts.query_source.source_path:match("([^/]+)$") or opts.query_source.source_path
		source = source .. (opts.query_source.source_type or "block") .. " " .. filename .. "#L" .. opts.query_source.source_line
	elseif opts.query_source and opts.query_source.source_type then
		source = source .. opts.query_source.source_type
	elseif opts.query_source then
		source = source .. tostring(opts.query_source)
	else
		source = source .. "manual"
	end

	local lines = {
		title,
		source,
		"",
		"o queries  [q previous query  ]q next query  gq query source",
	}
	if toolbar_visible(opts) then
		table.insert(lines, "Toolbar: f filter description  c clear filter  y copy markdown  Y copy with backlinks")
		if trim(opts.toolbar_filter) ~= "" then
			table.insert(lines, "Filter: description includes " .. trim(opts.toolbar_filter))
		end
	end
	table.insert(lines, "<space> toggle  e edit  s status  p postpone  <c-s> save  <c-r> refresh  gd task source  q close")
	table.insert(lines, "")
	return lines
end

function M.format_task_body(task, opts)
	if not has_layout_directives(opts) then
		return task.display_text or task.body or task.text or ""
	end

	local parts = {}
	local description = M.should_show(opts, "tags", true) and (task.description or task.text or task.body or "")
		or description_without_tags(task)
	append_part(parts, description)

	if M.should_show(opts, "recurrence rule", true) then
		append_part(parts, metadata_part("🔁", task.recurrence_rule, opts))
	end
	if M.should_show(opts, "on completion", true) then
		append_part(parts, metadata_part("🏁", task.on_completion, opts))
	end
	for _, spec in ipairs(DATE_DISPLAY) do
		if M.should_show(opts, spec.field, true) then
			append_part(parts, metadata_part(spec.symbol, task[spec.key], opts))
		end
	end
	if M.should_show(opts, "urgency", false) then
		append_part(parts, (short_mode(opts) and "" or "urgency ") .. urgency.format(task))
	end
	if M.should_show(opts, "id", true) then
		append_part(parts, metadata_part("🆔", task.id, opts))
	end
	if M.should_show(opts, "depends on", true) then
		append_part(parts, metadata_part("⛔", table.concat(task.depends_on or {}, ", "), opts))
	end
	append_part(parts, task.block_link)

	return table.concat(parts, " ")
end

-- Format task for display
function M.format_task_for_display(task, index, opts)
	opts = opts or {}
	-- Format priority label (if not normal)
	local priority_text = ""
	if M.should_show(opts, "priority", true) and task.priority and task.priority ~= "normal" then
		if short_mode(opts) then
			priority_text = (task_model.PRIORITY_SYMBOLS[task.priority] or "") .. " "
		else
			priority_text = "[" .. task.priority:upper() .. "] "
		end
	end
	local task_text = M.format_task_body(task, opts)

	local display_text = string.format(
		"%s%d. %s %s%s",
		opts.display_prefix or "",
		index,
		task.status,
		priority_text,
		task_text:gsub("^%[.?%] ", "") -- Remove task status part
	)

	-- Add file path info as wiki link (for internal tracking and navigation)
	if M.should_show(opts, "backlink", true) then
		local metadata = string.format(" [[%s#L%d]]", task.file_path, task.line_number)
		return display_text .. metadata
	end
	return display_text
end

local function tree_indent(value)
	return ((value or ""):gsub("\t", "    "):gsub(">", ""))
end

local function task_with_prefix(task, index, prefix, opts)
	local task_opts = vim.tbl_extend("force", opts or {}, {
		display_prefix = prefix,
	})
	return M.format_task_for_display(task, index, task_opts)
end

local function format_list_item_for_display(item)
	local marker = item.list_marker or item.listMarker or "-"
	local description = item.description or ""
	local status_symbol = item.status_symbol or item.statusCharacter
	local checkbox = status_symbol and (" [" .. status_symbol .. "]") or ""
	local suffix = trim(description) ~= "" and (" " .. description) or ""
	return string.format("%s%s%s%s", tree_indent(item.indentation), marker, checkbox, suffix)
end

local function matched_task_set(tasks)
	local set = {}
	for _, task in ipairs(tasks or {}) do
		set[task] = true
	end
	return set
end

local function closest_matched_parent(node, task_set)
	local parent = node and node.parent or nil
	while parent do
		if parent.task and task_set[parent.task] then
			return parent
		end
		parent = parent.parent
	end
	return nil
end

local function format_tree_tasks(tasks, current_index, opts)
	local display_lines = {}
	local index_map = {}
	local task_set = matched_task_set(tasks)
	local rendered = {}

	local function append_node(node)
		if not node or rendered[node] then
			return
		end

		rendered[node] = true
		if node.task and task_set[node.task] then
			table.insert(display_lines, task_with_prefix(node.task, current_index, tree_indent(node.indentation), opts))
			index_map[current_index] = node.task
			current_index = current_index + 1
		else
			table.insert(display_lines, format_list_item_for_display(node))
		end

		for _, child in ipairs(node.children or {}) do
			append_node(child)
		end
	end

	for _, task in ipairs(tasks or {}) do
		local node = task.list_item or task.listItem
		if not node then
			table.insert(display_lines, M.format_task_for_display(task, current_index, opts))
			index_map[current_index] = task
			current_index = current_index + 1
		elseif not rendered[node] then
			local matched_parent = closest_matched_parent(node, task_set)
			if not matched_parent or rendered[matched_parent] then
				append_node(node)
			end
		end
	end

	return display_lines, index_map, current_index
end

function M.filter_tasks_for_toolbar(tasks, filter)
	filter = trim(filter)
	if filter == "" then
		return tasks or {}
	end

	local filtered = {}
	local needle = filter:lower()
	for _, task in ipairs(tasks or {}) do
		local description = (task.description or task.text or task.body or ""):lower()
		if description:find(needle, 1, true) then
			table.insert(filtered, task)
		end
	end
	return filtered
end

local function render_task_lines(tasks, opts)
	opts = opts or {}
	local group_by = opts.group_by or {}
	local grouped_tasks, group_order = parser.group_tasks(tasks or {}, group_by)
	return M.format_grouped_tasks(grouped_tasks, group_order, opts)
end

function M.render_tasks_to_buffer(buf, tasks, opts)
	opts = vim.tbl_extend("force", opts or {}, {})
	tasks = tasks or {}
	local visible_tasks = M.filter_tasks_for_toolbar(tasks, opts.toolbar_filter)
	opts.shown_count = #visible_tasks
	opts.total_count = opts.total_count or #tasks

	local display_lines, index_map = render_task_lines(visible_tasks, opts)
	local header_lines = build_header_lines(opts)
	local lines = {}
	for _, line in ipairs(header_lines) do
		table.insert(lines, line)
	end
	for _, line in ipairs(display_lines) do
		table.insert(lines, line)
	end

	core.task_index_map[buf] = index_map
	M.buffer_header_line_count[buf] = #header_lines
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	return display_lines, index_map
end

-- Format grouped tasks for display
function M.format_grouped_tasks(grouped_tasks, group_order, opts)
	-- require('plenary.log').info('[xxxhhh][format grouped_tasks]', grouped_tasks, group_order, opts)
	opts = opts or {}
	local use_hierarchical_headings = opts.hierarchical_headings or false

	local display_lines = {}
	local index_map = {} -- Map display indices to original tasks
	local current_index = 1

	-- For hierarchical headings, we need to track which headings we've already displayed
	local displayed_headings = {}

	-- Process each group
	for _, group_name in ipairs(group_order) do
		local tasks = grouped_tasks[group_name]

		-- Add group title (if not default group)
		if group_name ~= "default" then
			table.insert(display_lines, "")

			if use_hierarchical_headings then
				-- For hierarchical headings, determine the heading level based on the number of colons
				local parts = {}
				for part in group_name:gmatch("[^:]+") do
					table.insert(parts, part)
				end

				-- Build up the heading path as we go
				local current_path = ""

				-- Add all parts as separate headings with appropriate levels, but only if not already displayed
				for i, part in ipairs(parts) do
					local level = i + 1 -- Start at level 2
					if level > 6 then
						level = 6
					end -- Max heading level is 6

					-- Build the current path to this heading level
					if current_path == "" then
						current_path = part
					else
						current_path = current_path .. ":" .. part
					end

					-- Only display this heading if we haven't seen it before
					if not displayed_headings[current_path] then
						table.insert(display_lines, string.rep("#", level) .. " " .. part)
						displayed_headings[current_path] = true
					end
				end
			else
				-- Traditional flat heading style
				table.insert(display_lines, "## " .. group_name:gsub(":", " > "))
			end
		end

		-- Process tasks in group
		if tree_enabled(opts) then
			local tree_lines, tree_index_map
			tree_lines, tree_index_map, current_index = format_tree_tasks(tasks, current_index, opts)
			for _, line in ipairs(tree_lines) do
				table.insert(display_lines, line)
			end
			for index, task in pairs(tree_index_map) do
				index_map[index] = task
			end
		else
			for _, task in ipairs(tasks) do
				local formatted_line = M.format_task_for_display(task, current_index, opts)
				table.insert(display_lines, formatted_line)
				index_map[current_index] = task
				current_index = current_index + 1
			end
		end
	end

	-- require('plenary.log').info('[xxxhhh][display lines]', display_lines)
	return display_lines, index_map
end

-- Refresh the current task list
function M.refresh_tasks_view()
	local buf = vim.api.nvim_get_current_buf()
	local tasks = core.buffer_tasks[buf]

	-- Store current window and cursor position
	local win = vim.api.nvim_get_current_win()
	local cursor_pos = vim.api.nvim_win_get_cursor(win)

	-- Get the first task's file path to determine vault path
	local finder_opts = M.buffer_finder_opts[buf] or M.last_finder_opts or {}
	local vault_path = finder_opts.vault_path

	if not vault_path then
		vim.notify("Could not determine vault path for refresh", vim.log.levels.ERROR)
		return
	end

	-- Check if we're in a floating window
	local win_config = vim.api.nvim_win_get_config(win)
	local is_float = win_config.relative and win_config.relative ~= ""

	-- Get current buffer options to preserve them
	local hierarchical_headings = false

	-- Try to determine current grouping from buffer content
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	for _, line in ipairs(lines) do
		if line:match("^## ") then
			-- Found a heading, check if it's hierarchical
			if line:match("> ") then
				-- Traditional flat heading with ">"
				hierarchical_headings = false
			else
				-- Likely hierarchical
				hierarchical_headings = true
			end
			break
		end
	end

	-- Re-run the finder with the same options as before
	local finder = require("obsidian-tasks.finder")

	-- Create options table for the finder
	local opts = {
		vault_path = vault_path,
		float = is_float,
		global_filter = finder_opts.global_filter,
		hierarchical_headings = hierarchical_headings,
		reuse_buffer = buf,
	}

	-- Reuse the last filter and group_by settings if available
	for key, value in pairs(finder_opts) do
		if opts[key] == nil then
			opts[key] = value
		end
	end

	finder.find_tasks(opts)

	if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) then
		local line_count = vim.api.nvim_buf_line_count(buf)
		local row = math.min(cursor_pos[1], line_count)
		pcall(vim.api.nvim_win_set_cursor, win, { row, cursor_pos[2] })
	end

	-- Notify user
	vim.notify("Tasks refreshed", vim.log.levels.INFO)
end

local function display_opts_for_buffer(buf)
	local finder_opts = M.buffer_finder_opts[buf] or {}
	local opts = vim.tbl_extend("force", M.buffer_display_opts[buf] or {}, {})
	opts.group_by = opts.group_by or finder_opts.group_by or {}
	opts.toolbar_filter = finder_opts.toolbar_filter
	return opts
end

function M.redraw_tasks_buffer(buf, opts)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	if vim.api.nvim_get_option_value("modified", { buf = buf }) then
		vim.notify("Save task changes before filtering results", vim.log.levels.WARN)
		return false
	end

	local tasks = core.buffer_tasks[buf]
	if not tasks then
		vim.notify("No tasks associated with this buffer", vim.log.levels.ERROR)
		return false
	end

	opts = opts or display_opts_for_buffer(buf)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	M.render_tasks_to_buffer(buf, tasks, opts)
	vim.api.nvim_set_option_value("modified", false, { buf = buf })
	return true
end

function M.set_toolbar_filter(buf, value)
	buf = buf or vim.api.nvim_get_current_buf()
	local finder_opts = M.buffer_finder_opts[buf] or {}
	finder_opts.toolbar_filter = trim(value)
	if finder_opts.toolbar_filter == "" then
		finder_opts.toolbar_filter = nil
	end
	M.buffer_finder_opts[buf] = finder_opts
	return M.redraw_tasks_buffer(buf)
end

function M.clear_toolbar_filter(buf)
	return M.set_toolbar_filter(buf, "")
end

function M.prompt_toolbar_filter(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local finder_opts = M.buffer_finder_opts[buf] or {}
	vim.ui.input({
		prompt = "Task description filter: ",
		default = finder_opts.toolbar_filter or "",
	}, function(input)
		if input ~= nil then
			M.set_toolbar_filter(buf, input)
		end
	end)
end

local function result_body_lines(buf)
	local header_count = M.buffer_header_line_count[buf] or 0
	return vim.api.nvim_buf_get_lines(buf, header_count, -1, false)
end

local function strip_backlink(line)
	return (line:gsub("%s+%[%[[^%]]+#L%d+%]%]$", ""))
end

local function markdown_line_from_display(buf, line, include_backlinks)
	local index = tonumber(line:match("^%s*(%d+)%. "))
	local markdown = line:gsub("^(%s*)%d+%.%s+", "%1- ", 1)
	if not include_backlinks then
		return strip_backlink(markdown)
	end

	if index and not markdown:match("%[%[[^%]]+#L%d+%]%]$") then
		local task = (core.task_index_map[buf] or {})[index]
		if task and task.file_path and task.line_number then
			markdown = markdown .. string.format(" [[%s#L%d]]", task.file_path, task.line_number)
		end
	end
	return markdown
end

function M.markdown_lines(buf, opts)
	buf = buf or vim.api.nvim_get_current_buf()
	opts = opts or {}
	local lines = {}
	for _, line in ipairs(result_body_lines(buf)) do
		table.insert(lines, markdown_line_from_display(buf, line, opts.include_backlinks == true))
	end
	return lines
end

function M.copy_markdown(buf, opts)
	buf = buf or vim.api.nvim_get_current_buf()
	opts = opts or {}
	local lines = M.markdown_lines(buf, opts)
	vim.fn.setreg(opts.register or '"', table.concat(lines, "\n"))
	vim.notify(string.format("Copied %d task result line(s)", #lines), vim.log.levels.INFO)
	return lines
end

local function clear_toolbar_keymaps(buf)
	for _, lhs in ipairs({ "f", "c", "y", "Y" }) do
		pcall(vim.keymap.del, "n", lhs, { buffer = buf })
	end
end

-- Set up editable buffer
function M.setup_editable_buffer(buf, tasks, opts)
	opts = opts or {}
	-- Set buffer options
	vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf }) -- Make editable
	vim.api.nvim_set_option_value("filetype", "obstasks", { buf = buf }) -- Set custom filetype

	local augroup = vim.api.nvim_create_augroup("ObsidianTasksBuffer" .. buf, { clear = true })

	-- Apply changes on save
	vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
		group = augroup,
		buffer = buf,
		callback = function()
			if core.save_tasks_changes(buf, tasks) then
				vim.api.nvim_set_option_value("modified", false, { buf = buf })
			end
		end,
	})

	-- Keyboard mappings
	vim.api.nvim_buf_set_keymap(buf, "n", "q", ":bd!<CR>", { noremap = true, silent = true })

	local obsidian_tasks = require("obsidian-tasks")
	vim.keymap.set({ "n" }, "<c-s>", obsidian_tasks.save_current_tasks, { buffer = buf, noremap = true, silent = true })

	-- Add refresh functionality
	vim.keymap.set({ "n" }, "<c-r>", M.refresh_tasks_view, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set({ "n" }, "o", function()
		require("obsidian-tasks.panel").select_query({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Select query" })

	vim.keymap.set({ "n" }, "]q", function()
		require("obsidian-tasks.panel").next_query({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Next query" })

	vim.keymap.set({ "n" }, "[q", function()
		require("obsidian-tasks.panel").previous_query({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Previous query" })

	vim.keymap.set({ "n" }, "gq", function()
		require("obsidian-tasks.panel").go_to_query_source({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Go to query source" })

	clear_toolbar_keymaps(buf)
	if toolbar_visible(opts) then
		vim.keymap.set("n", "f", function()
			M.prompt_toolbar_filter(buf)
		end, { buffer = buf, noremap = true, silent = true, desc = "Filter task results" })
		vim.keymap.set("n", "c", function()
			M.clear_toolbar_filter(buf)
		end, { buffer = buf, noremap = true, silent = true, desc = "Clear task result filter" })
		vim.keymap.set("n", "y", function()
			M.copy_markdown(buf, { include_backlinks = false })
		end, { buffer = buf, noremap = true, silent = true, desc = "Copy task results" })
		vim.keymap.set("n", "Y", function()
			M.copy_markdown(buf, { include_backlinks = true })
		end, { buffer = buf, noremap = true, silent = true, desc = "Copy task results with backlinks" })
	end

	-- Toggle task status
	vim.keymap.set(
		{ "n" },
		"<space>",
		obsidian_tasks.toggle_task_at_cursor,
		{ noremap = true, silent = true, buffer = buf }
	)

	vim.keymap.set({ "n" }, "s", function()
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

	vim.keymap.set({ "n" }, "p", function()
		require("obsidian-tasks").postpone_task_at_cursor()
	end, { buffer = buf, noremap = true, silent = true, desc = "Postpone task" })

	vim.keymap.set({ "n" }, "e", function()
		require("obsidian-tasks").edit_current_task()
	end, { buffer = buf, noremap = true, silent = true, desc = "Edit task" })

	-- Add jump to task source file functionality for gd and gf
	local function jump_to_task_source()
		local line = vim.api.nvim_get_current_line()
		local file_path, line_number = line:match("%[%[([^#]+)#L(%d+)%]%]")

		if not file_path then
			local index = tonumber(line:match("^%s*(%d+)%. "))
			local task = index and (core.task_index_map[buf] or {})[index] or nil
			file_path = task and task.file_path or nil
			line_number = task and task.line_number or nil
		end

		if file_path and line_number then
			-- Close current buffer
			vim.cmd("bd")
			-- Open the source file at the specified line
			vim.cmd("edit +" .. line_number .. " " .. vim.fn.fnameescape(file_path))
		end
	end

	-- Map both gd and gf to the jump function
	vim.keymap.set({ "n" }, "gd", jump_to_task_source, { noremap = true, silent = true, buffer = buf })
	vim.keymap.set({ "n" }, "gf", jump_to_task_source, { noremap = true, silent = true, buffer = buf })

	-- Add navigation between tasks with J and K
	local function move_to_task(direction)
		local current_line = vim.api.nvim_win_get_cursor(0)[1]
		local line_count = vim.api.nvim_buf_line_count(buf)
		local target_line = current_line

		-- Skip help lines at the top
		local help_lines_count = M.buffer_header_line_count[buf] or #M.TASK_VIEW_HELP_LINES

		-- Function to check if a line contains a task
		local function is_task_line(line_num)
			if line_num <= 0 or line_num > line_count then
				return false
			end

			local line_content = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1]
			-- Check if line matches task pattern (starts with a number followed by dot and status)
			return line_content:match("^%s*%d+%. %[.?%]")
		end

		if direction == "next" then
			-- Find next task line
			for i = current_line + 1, line_count do
				if is_task_line(i) then
					target_line = i
					break
				end
			end
		else -- direction == "prev"
			-- Find previous task line
			for i = current_line - 1, help_lines_count + 1, -1 do
				if is_task_line(i) then
					target_line = i
					break
				end
			end
		end

		-- Move cursor to target line
		if target_line ~= current_line then
			vim.api.nvim_win_set_cursor(0, { target_line, 0 })
			-- Center the cursor in the window
			vim.cmd("normal! zz")
		end
	end

	-- Add J and K keybindings for task navigation
	vim.keymap.set({ "n" }, "J", function()
		move_to_task("next")
	end, { noremap = true, silent = true, buffer = buf, desc = "Move to next task" })
	vim.keymap.set({ "n" }, "K", function()
		move_to_task("prev")
	end, { noremap = true, silent = true, buffer = buf, desc = "Move to previous task" })
end

-- Display editable task list
function M.display_tasks(tasks, grouped_tasks, group_order, opts)
	opts = opts or {}

	-- Create a new buffer
	local buf = create_or_reuse_buffer(opts, true)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

	-- Store task list association with buffer
	core.buffer_tasks[buf] = tasks
	M.buffer_finder_opts[buf] = opts.finder_opts or M.last_finder_opts
	M.buffer_display_opts[buf] = opts

	-- Set buffer content
	M.render_tasks_to_buffer(buf, tasks, opts)

	-- Make buffer editable
	M.setup_editable_buffer(buf, tasks, opts)

	-- Reset the modified flag after setting content
	vim.api.nvim_set_option_value("modified", false, { buf = buf })

	-- Open a new window and set to current buffer
	vim.api.nvim_set_current_buf(buf)

	-- Clean up task list association when buffer is deleted
	vim.api.nvim_create_autocmd({ "BufDelete" }, {
		buffer = buf,
		callback = function()
			core.buffer_tasks[buf] = nil
			core.task_index_map[buf] = nil
			M.buffer_finder_opts[buf] = nil
			M.buffer_display_opts[buf] = nil
			M.buffer_header_line_count[buf] = nil
		end,
		once = true,
	})
end

-- Display editable task list in floating window
function M.display_tasks_float(tasks, grouped_tasks, group_order, opts)
	opts = opts or {}

	-- Create a new buffer
	local buf = create_or_reuse_buffer(opts, false)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

	-- Store task list association with buffer
	core.buffer_tasks[buf] = tasks
	M.buffer_finder_opts[buf] = opts.finder_opts or M.last_finder_opts
	M.buffer_display_opts[buf] = opts

	-- Set buffer content
	local display_lines = M.render_tasks_to_buffer(buf, tasks, opts)

	-- Make buffer editable
	M.setup_editable_buffer(buf, tasks, opts)

	-- Reset the modified flag after setting content
	vim.api.nvim_set_option_value("modified", false, { buf = buf })

	-- Calculate window size and position
	local width = math.max(80, math.floor(vim.o.columns * 0.8))
	local height = math.min(math.max(#display_lines + (M.buffer_header_line_count[buf] or 6) + 1, 8), vim.o.lines - 4)
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Window options
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
	}

	-- Create floating window
	local win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Set window options
	vim.api.nvim_set_option_value("winhl", "NormalFloat:Normal", { win = win })

	-- Create autocmd to remind saving when leaving buffer
	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		buffer = buf,
		callback = function()
			if vim.api.nvim_get_option_value("modified", { buf = buf }) then
				local choice = vim.fn.confirm("Save changes?", "&Yes\n&No\n&Cancel", 1)
				if choice == 1 then -- Yes
					require("obsidian-tasks").save_current_tasks()
				elseif choice == 3 then -- Cancel
					return true -- Prevent leaving
				end
			end

			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
		once = true,
	})

	-- Clean up task list association when buffer is deleted
	vim.api.nvim_create_autocmd({ "BufDelete" }, {
		buffer = buf,
		callback = function()
			core.buffer_tasks[buf] = nil
			core.task_index_map[buf] = nil
			M.buffer_finder_opts[buf] = nil
			M.buffer_display_opts[buf] = nil
			M.buffer_header_line_count[buf] = nil
		end,
		once = true,
	})
end

function M.display_query_errors(errors, opts)
	opts = opts or {}
	local buf = create_or_reuse_buffer(opts, true)
	M.buffer_finder_opts[buf] = opts.finder_opts or M.last_finder_opts
	core.buffer_tasks[buf] = {}
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "obstasks", { buf = buf })

	local lines = {
		"Tasks: " .. (opts.query_name or "Query error"),
		"Source: " .. (opts.query_source and (opts.query_source.source_type or tostring(opts.query_source)) or "manual"),
		"",
		"Query errors:",
		"",
	}

	for _, err in ipairs(errors or {}) do
		table.insert(lines, string.format("- line %d: %s", err.line_number or 0, err.message or "Unknown error"))
		if err.line and err.line ~= "" then
			table.insert(lines, "  " .. err.line)
		end
	end

	if #errors == 0 then
		table.insert(lines, "- Unknown query error")
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.keymap.set({ "n" }, "q", ":bd!<CR>", { buffer = buf, noremap = true, silent = true })
	vim.api.nvim_set_current_buf(buf)
end

return M
