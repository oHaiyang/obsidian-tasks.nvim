local M = {}

local date = require("obsidian-tasks.date")
local parser = require("obsidian-tasks.parser")
local status = require("obsidian-tasks.status")
local task_model = require("obsidian-tasks.task")

M.form_state = {}

local FIELD_ORDER = {
	"description",
	"status",
	"priority",
	"created",
	"start",
	"scheduled",
	"due",
	"done",
	"cancelled",
	"recurrence",
	"id",
	"depends_on",
	"on_completion",
}

local FIELD_LABELS = {
	description = "description",
	status = "status",
	priority = "priority",
	created = "created",
	start = "start",
	scheduled = "scheduled",
	due = "due",
	done = "done",
	cancelled = "cancelled",
	recurrence = "recurrence",
	id = "id",
	depends_on = "depends_on",
	on_completion = "on_completion",
}

local DATE_SYMBOLS = {
	created = "➕",
	start = "🛫",
	scheduled = "⏳",
	due = "📅",
	done = "✅",
	cancelled = "❌",
}

local DATE_FIELDS = {
	"created",
	"start",
	"scheduled",
	"due",
	"done",
	"cancelled",
}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function date_opts(state)
	return {
		today = (state and state.today) or get_config().today,
	}
end

local function read_file_lines(file_path)
	local file = io.open(file_path, "r")
	if not file then
		return nil, "Cannot open file: " .. file_path
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()
	return lines
end

local function write_file_lines(file_path, lines)
	local file = io.open(file_path, "w")
	if not file then
		return false, "Cannot write to file: " .. file_path
	end
	for _, line in ipairs(lines) do
		file:write(line .. "\n")
	end
	file:close()
	return true
end

local function priority_symbol(priority)
	if not priority or priority == "" or priority == "normal" or priority == "none" then
		return nil
	end
	return task_model.PRIORITY_SYMBOLS[priority:lower()]
end

local function normalize_priority(priority)
	priority = trim(priority):lower()
	if priority == "" then
		return ""
	end
	if priority == "none" then
		return "normal"
	end
	return priority
end

local function task_to_fields(task)
	local status_entry = status.get(task.status_symbol or task.status, get_config())
	return {
		description = task.description or task.text or task.display_text or "",
		status = status_entry.name,
		priority = task.priority ~= "normal" and task.priority or "",
		created = task.created_date or "",
		start = task.start_date or "",
		scheduled = task.scheduled_date or "",
		due = task.due_date or "",
		done = task.done_date or "",
		cancelled = task.cancelled_date or "",
		recurrence = task.recurrence_rule or "",
		id = task.id or "",
		depends_on = table.concat(task.depends_on or task.dependsOn or {}, ", "),
		on_completion = task.on_completion or "",
	}
end

local function empty_fields(opts)
	opts = opts or {}
	local fields = {
		description = "",
		status = "Todo",
		priority = "",
		created = "",
		start = "",
		scheduled = "",
		due = "",
		done = "",
		cancelled = "",
		recurrence = "",
		id = "",
		depends_on = "",
		on_completion = "",
	}

	if get_config().set_created_date then
		fields.created = date.parse_date_expr("today", { today = opts.today or get_config().today }) or date.today()
	end
	return fields
end

local function form_lines(fields, mode)
	local lines = {
		"# Obsidian Tasks " .. (mode == "create" and "Create Task" or "Edit Task"),
		"# Edit values after ':' and save with <C-S> or :write. Date fields accept today/tomorrow/+N/2 weeks/6 oct.",
		"# Shortcuts: gs pick status, gd pick date on a date field, q close.",
		"",
	}
	for _, key in ipairs(FIELD_ORDER) do
		table.insert(lines, FIELD_LABELS[key] .. ": " .. (fields[key] or ""))
	end
	return lines
end

local function parse_form_lines(lines)
	local fields = {}
	for _, line in ipairs(lines) do
		if not line:match("^%s*#") then
			local key, value = line:match("^([%w_]+):%s*(.*)$")
			if key then
				fields[key] = trim(value)
			end
		end
	end
	return fields
end

local function normalize_date_fields(fields, state)
	for _, field in ipairs(DATE_FIELDS) do
		local value = trim(fields[field])
		if value ~= "" then
			local parsed = date.parse_date_expr(value, date_opts(state))
			if not parsed then
				return false, "Invalid " .. field .. " date: " .. value
			end
			fields[field] = parsed
		end
	end
	return true
end

local function current_field(buf)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	return line:match("^([%w_]+):")
end

local function set_form_field(buf, key, value)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	for index, line in ipairs(lines) do
		if line:match("^" .. key .. ":") then
			lines[index] = key .. ": " .. (value or "")
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.api.nvim_set_option_value("modified", true, { buf = buf })
			return true
		end
	end
	return false
end

function M.pick_status(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local entries = status.registry(get_config())
	vim.ui.select(entries, {
		prompt = "Task status",
		format_item = function(entry)
			return string.format("[%s] %s (%s)", entry.symbol, entry.name, entry.type)
		end,
	}, function(entry)
		if entry then
			set_form_field(buf, "status", entry.name)
		end
	end)
end

function M.pick_date(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local field = current_field(buf)
	if not field or not DATE_SYMBOLS[field] then
		vim.notify("Move cursor to a date field first", vim.log.levels.WARN)
		return
	end

	local state = M.form_state[buf] or {}
	local choices = {
		{ label = "Clear", value = "" },
		{ label = "Today", expr = "today" },
		{ label = "Tomorrow", expr = "tomorrow" },
		{ label = "In 1 week", expr = "1 week" },
		{ label = "In 2 weeks", expr = "2 weeks" },
		{ label = "In 1 month", expr = "1 month" },
	}
	vim.ui.select(choices, {
		prompt = field .. " date",
		format_item = function(item)
			return item.label
		end,
	}, function(item)
		if not item then
			return
		end
		local value = item.value
		if value == nil then
			value = date.parse_date_expr(item.expr, date_opts(state)) or item.expr
		end
		set_form_field(buf, field, value)
	end)
end

local function append_part(parts, value)
	value = trim(value)
	if value ~= "" then
		table.insert(parts, value)
	end
end

local function build_body(fields)
	local parts = {}
	append_part(parts, fields.description)

	local priority = normalize_priority(fields.priority)
	local priority_emoji = priority_symbol(priority)
	if priority_emoji then
		append_part(parts, priority_emoji)
	end

	if trim(fields.recurrence) ~= "" then
		append_part(parts, "🔁 " .. trim(fields.recurrence))
	end
	if trim(fields.on_completion) ~= "" then
		append_part(parts, "🏁 " .. trim(fields.on_completion))
	end

	for _, field in ipairs({ "created", "start", "scheduled", "due", "done", "cancelled" }) do
		local value = trim(fields[field])
		if value ~= "" then
			append_part(parts, DATE_SYMBOLS[field] .. " " .. value)
		end
	end

	if trim(fields.id) ~= "" then
		append_part(parts, "🆔 " .. trim(fields.id))
	end
	if trim(fields.depends_on) ~= "" then
		append_part(parts, "⛔ " .. trim(fields.depends_on))
	end

	return table.concat(parts, " ")
end

local function build_task_line(fields, state)
	local symbol = status.resolve_symbol(fields.status, get_config()) or status.normalize_symbol(fields.status)
	local task = {
		indentation = state.indentation or "",
		list_marker = state.list_marker or "-",
		status_symbol = symbol,
		body = build_body(fields),
	}
	return task_model.serialize(task)
end

local function current_display_task(buf)
	local line = vim.api.nvim_get_current_line()
	local parsed = parser.parse_display_line(line)
	if not parsed then
		return nil
	end

	local index_map = require("obsidian-tasks.core").task_index_map[buf] or {}
	return parsed.index and index_map[parsed.index] or nil
end

local function open_form(fields, state)
	local buf = vim.api.nvim_create_buf(true, false)
	M.form_state[buf] = state
	vim.api.nvim_buf_set_name(buf, "obsidian-tasks://form/" .. state.mode)
	vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "obstasks-form", { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, form_lines(fields, state.mode))
	vim.api.nvim_set_option_value("modified", false, { buf = buf })

	local group = vim.api.nvim_create_augroup("ObsidianTasksForm" .. buf, { clear = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = group,
		buffer = buf,
		callback = function()
			M.save_form(buf)
		end,
	})

	vim.keymap.set("n", "<c-s>", function()
		M.save_form(buf)
	end, { buffer = buf, noremap = true, silent = true, desc = "Save task form" })
	vim.keymap.set("n", "q", ":bd!<CR>", { buffer = buf, noremap = true, silent = true, desc = "Close task form" })
	vim.keymap.set("n", "gs", function()
		M.pick_status(buf)
	end, { buffer = buf, noremap = true, silent = true, desc = "Pick task status" })
	vim.keymap.set("n", "gd", function()
		M.pick_date(buf)
	end, { buffer = buf, noremap = true, silent = true, desc = "Pick date" })

	vim.api.nvim_set_current_buf(buf)
	return buf
end

local function save_to_source_buffer(state, line)
	if not (state.source_buf and vim.api.nvim_buf_is_valid(state.source_buf)) then
		return false, "Source buffer is no longer valid"
	end

	local row = state.line_number
	if state.mode == "create" then
		vim.api.nvim_buf_set_lines(state.source_buf, row, row, false, { line })
	else
		vim.api.nvim_buf_set_lines(state.source_buf, row - 1, row, false, { line })
	end
	vim.api.nvim_set_option_value("modified", true, { buf = state.source_buf })
	return true
end

local function save_to_file(state, line)
	local file_path = state.file_path
	local lines, read_err = read_file_lines(file_path)
	if not lines then
		return false, read_err
	end

	if state.mode == "create" then
		table.insert(lines, (state.line_number or #lines) + 1, line)
	else
		if not lines[state.line_number] then
			return false, "Line not found in file: " .. file_path
		end
		lines[state.line_number] = line
	end

	return write_file_lines(file_path, lines)
end

function M.save_form(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local state = M.form_state[buf]
	if not state then
		vim.notify("No task form state for this buffer", vim.log.levels.ERROR)
		return false
	end

	local fields = parse_form_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	if trim(fields.description) == "" then
		vim.notify("Task description is required", vim.log.levels.ERROR)
		return false
	end
	local dates_ok, date_err = normalize_date_fields(fields, state)
	if not dates_ok then
		vim.notify(date_err, vim.log.levels.ERROR)
		return false
	end

	local line = build_task_line(fields, state)
	local ok, err
	if state.source_buf and vim.api.nvim_buf_is_valid(state.source_buf) then
		ok, err = save_to_source_buffer(state, line)
	else
		ok, err = save_to_file(state, line)
	end

	if not ok then
		vim.notify(err or "Failed to save task", vim.log.levels.ERROR)
		return false
	end

	vim.api.nvim_set_option_value("modified", false, { buf = buf })
	vim.notify(state.mode == "create" and "Task created" or "Task updated", vim.log.levels.INFO)
	pcall(vim.api.nvim_buf_delete, buf, { force = true })
	return true
end

function M.edit_current_task()
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
	local task = task_model.parse_line({
		line = line,
		file_path = vim.api.nvim_buf_get_name(buf),
		line_number = row,
		global_filter = "",
	})
	local state

	if task then
		state = {
			mode = "edit",
			source_buf = buf,
			file_path = vim.api.nvim_buf_get_name(buf),
			line_number = row,
			indentation = task.indentation,
			list_marker = task.list_marker,
			today = get_config().today,
		}
	else
		task = current_display_task(buf)
		if not task then
			vim.notify("Cursor is not on a task", vim.log.levels.ERROR)
			return nil
		end
		state = {
			mode = "edit",
			file_path = task.file_path,
			line_number = task.line_number,
			indentation = task.indentation,
			list_marker = task.list_marker,
			today = get_config().today,
		}
	end

	return open_form(task_to_fields(task), state)
end

function M.create_task(opts)
	opts = opts or {}
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local file_path = opts.file_path or vim.api.nvim_buf_get_name(buf)
	local source_buf = buf

	if file_path == "" or vim.bo[buf].buftype ~= "" or not file_path:match("%.md$") then
		file_path = opts.file_path or get_config().inbox_file
		source_buf = nil
	end

	if not file_path or file_path == "" then
		vim.notify("Open a Markdown file or configure inbox_file to create tasks", vim.log.levels.ERROR)
		return nil
	end

	return open_form(empty_fields({ today = opts.today }), {
		mode = "create",
		source_buf = source_buf,
		file_path = file_path,
		line_number = source_buf and row or nil,
		indentation = "",
		list_marker = "-",
		today = opts.today,
	})
end

return M
