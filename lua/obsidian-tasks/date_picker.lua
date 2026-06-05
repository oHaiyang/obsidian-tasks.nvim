local M = {}

local date = require("obsidian-tasks.date")
local task_model = require("obsidian-tasks.task")

local FIELD_SYMBOLS = {
	created = "➕",
	start = "🛫",
	scheduled = "⏳",
	due = "📅",
	done = "✅",
	cancelled = "❌",
}

local FIELD_ALIASES = {
	["created date"] = "created",
	["start date"] = "start",
	["scheduled date"] = "scheduled",
	["due date"] = "due",
	["done date"] = "done",
	["cancelled date"] = "cancelled",
}

local MONTH_NAMES = {
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function rstrip(value)
	return (value or ""):gsub("%s+$", "")
end

local function get_config()
	local ok, plugin = pcall(require, "obsidian-tasks")
	if ok and plugin then
		return plugin.config or {}
	end
	return {}
end

local function date_picker_config()
	local config = get_config()
	local picker = config.date_picker or config.datePicker or {}
	if type(picker) == "string" then
		picker = { style = picker }
	end
	return type(picker) == "table" and picker or {}
end

local function normalize_field(field)
	field = trim(field):lower():gsub("_", " ")
	return FIELD_ALIASES[field] or field:gsub("%s+", "_")
end

local function date_opts(state)
	return {
		today = (state and state.today) or get_config().today,
	}
end

local function parse_ymd(value)
	local year, month, day = tostring(value or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	return tonumber(year), tonumber(month), tonumber(day)
end

local function is_leap_year(year)
	return year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)
end

local function days_in_month(year, month)
	local days = {
		31,
		is_leap_year(year) and 29 or 28,
		31,
		30,
		31,
		30,
		31,
		31,
		30,
		31,
		30,
		31,
	}
	return days[month]
end

local function make_date(year, month, day)
	local max_day = days_in_month(year, month)
	if not max_day then
		return nil
	end
	return string.format("%04d-%02d-%02d", year, month, math.min(math.max(day, 1), max_day))
end

local function weekday_monday0(value)
	local year, month, day = parse_ymd(value)
	if not year then
		return nil
	end
	local sunday0 = tonumber(os.date("%w", os.time({
		year = year,
		month = month,
		day = day,
		hour = 12,
		min = 0,
		sec = 0,
	})))
	return (sunday0 + 6) % 7
end

local function valid_or_today(value, state)
	if date.is_valid(value) then
		return value
	end
	local today = date_opts(state).today or date.today()
	if date.is_valid(today) then
		return today
	end
	return date.today()
end

local function picker_style(opts)
	opts = opts or {}
	if opts.calendar == true then
		return "calendar"
	end
	if opts.style then
		return opts.style
	end
	return date_picker_config().style or "select"
end

function M.choices(opts)
	opts = opts or {}
	local choices = {
		{ label = "Clear", value = "" },
		{ label = "Today", expr = "today" },
		{ label = "Tomorrow", expr = "tomorrow" },
		{ label = "Yesterday", expr = "yesterday" },
		{ label = "Next week", expr = "next week" },
		{ label = "In 1 week", expr = "1 week" },
		{ label = "In 2 weeks", expr = "2 weeks" },
		{ label = "Next month", expr = "next month" },
		{ label = "In 1 month", expr = "1 month" },
		{ label = "Custom...", custom = true },
	}
	if date.is_valid(opts.current_value) then
		table.insert(choices, 2, {
			label = "Advance 1 day",
			value = date.add_days(opts.current_value, -1),
		})
		table.insert(choices, 3, {
			label = "Postpone 1 day",
			value = date.add_days(opts.current_value, 1),
		})
	end
	if opts.calendar_choice ~= false then
		table.insert(choices, { label = "Calendar...", calendar = true })
	end
	return choices
end

function M.resolve_expr(expr, state)
	if expr == "" then
		return ""
	end
	return date.parse_date_expr(expr, date_opts(state))
end

function M.date_in_line(line, field)
	field = normalize_field(field or "due")
	local dataview_key = task_model.DATAVIEW_DATE_KEYS[field]
	if dataview_key then
		local value = task_model.dataview_field_value(line, dataview_key)
		if date.is_valid(value) then
			return value
		end
	end
	for _, symbol in ipairs(task_model.DATE_SYMBOLS[field] or { FIELD_SYMBOLS[field] }) do
		if symbol then
			local value = tostring(line or ""):match(symbol .. "%s*(%d%d%d%d%-%d%d%-%d%d)")
			if value then
				return value
			end
		end
	end
	return nil
end

function M.month_grid(value)
	value = valid_or_today(value)
	local year, month = parse_ymd(value)
	local first = make_date(year, month, 1)
	local offset = weekday_monday0(first) or 0
	local max_day = days_in_month(year, month)
	local weeks = {}
	local day = 1 - offset

	while day <= max_day do
		local week = {}
		for _ = 1, 7 do
			if day < 1 or day > max_day then
				table.insert(week, { day = nil, date = nil })
			else
				table.insert(week, {
					day = day,
					date = make_date(year, month, day),
				})
			end
			day = day + 1
		end
		table.insert(weeks, week)
	end

	return weeks
end

function M.calendar_state(opts)
	opts = opts or {}
	local selected = valid_or_today(opts.selected_date or opts.current_value, opts.state)
	local year, month = parse_ymd(selected)
	return {
		field = normalize_field(opts.field or "due"),
		selected_date = selected,
		current_value = opts.current_value,
		year = year,
		month = month,
		state = opts.state,
	}
end

local function calendar_cell_text(cell, selected)
	if not cell.day then
		return "    "
	end
	if cell.date == selected then
		return string.format("[%2d]", cell.day)
	end
	return string.format(" %2d ", cell.day)
end

function M.calendar_lines(state)
	state = state or M.calendar_state()
	local year, month = parse_ymd(state.selected_date)
	local lines = {
		string.format("%s %04d        field: %s", MONTH_NAMES[month] or "", year or 0, state.field or "due"),
		"Mo  Tu  We  Th  Fr  Sa  Su",
	}
	for _, week in ipairs(M.month_grid(state.selected_date)) do
		local cells = {}
		for _, cell in ipairs(week) do
			table.insert(cells, calendar_cell_text(cell, state.selected_date))
		end
		table.insert(lines, table.concat(cells, ""))
	end
	table.insert(lines, "")
	if date.is_valid(state.current_value) then
		table.insert(lines, "Current: " .. state.current_value)
	end
	table.insert(lines, "h/l day  j/k week  H/L month  <CR> select  c clear  q close")
	return lines
end

local function close_calendar(state)
	if state and state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	elseif state and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end
end

local function render_calendar(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local lines = M.calendar_lines(state)
	vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
end

function M.move_calendar_state(state, days)
	state.selected_date = valid_or_today(state.selected_date, state.state)
	state.selected_date = date.add_days(state.selected_date, days) or state.selected_date
	state.year, state.month = parse_ymd(state.selected_date)
	if state.buf then
		render_calendar(state)
	end
	return state
end

function M.move_calendar_month_state(state, months)
	state.selected_date = valid_or_today(state.selected_date, state.state)
	state.selected_date = date.add_months(state.selected_date, months) or state.selected_date
	state.year, state.month = parse_ymd(state.selected_date)
	if state.buf then
		render_calendar(state)
	end
	return state
end

function M.open_calendar(opts, callback)
	opts = opts or {}
	callback = callback or function() end
	local state = M.calendar_state(opts)
	state.buf = vim.api.nvim_create_buf(false, true)
	pcall(vim.api.nvim_buf_set_name, state.buf, "obsidian-tasks://date-picker")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = state.buf })
	vim.api.nvim_set_option_value("filetype", "obstasks-date-picker", { buf = state.buf })

	render_calendar(state)

	local width = 52
	local height = math.max(10, vim.api.nvim_buf_line_count(state.buf))
	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		row = math.max(0, math.floor((vim.o.lines - height) / 2)),
		style = "minimal",
		border = "rounded",
	})

	local function choose(value)
		close_calendar(state)
		callback(value)
	end
	local map_opts = { buffer = state.buf, noremap = true, silent = true }
	vim.keymap.set("n", "q", function()
		close_calendar(state)
	end, map_opts)
	vim.keymap.set("n", "<Esc>", function()
		close_calendar(state)
	end, map_opts)
	vim.keymap.set("n", "<CR>", function()
		choose(state.selected_date)
	end, map_opts)
	vim.keymap.set("n", "c", function()
		choose("")
	end, map_opts)
	vim.keymap.set("n", "h", function()
		M.move_calendar_state(state, -1)
	end, map_opts)
	vim.keymap.set("n", "l", function()
		M.move_calendar_state(state, 1)
	end, map_opts)
	vim.keymap.set("n", "k", function()
		M.move_calendar_state(state, -7)
	end, map_opts)
	vim.keymap.set("n", "j", function()
		M.move_calendar_state(state, 7)
	end, map_opts)
	vim.keymap.set("n", "H", function()
		M.move_calendar_month_state(state, -1)
	end, map_opts)
	vim.keymap.set("n", "L", function()
		M.move_calendar_month_state(state, 1)
	end, map_opts)

	return state
end

function M.pick(opts, callback)
	opts = opts or {}
	if picker_style(opts) == "calendar" then
		return M.open_calendar(opts, callback)
	end
	vim.ui.select(M.choices(opts), {
		prompt = opts.prompt or "Task date",
		format_item = function(item)
			return item.label
		end,
	}, function(item)
		if not item then
			return
		end
		if item.calendar then
			M.open_calendar(opts, callback)
			return
		end
		if item.custom then
			vim.ui.input({ prompt = "Date: " }, function(input)
				if input == nil then
					return
				end
				local parsed = M.resolve_expr(input, opts.state)
				if not parsed then
					vim.notify("Invalid date: " .. input, vim.log.levels.ERROR)
					return
				end
				callback(parsed)
			end)
			return
		end

		local value = item.value
		if value == nil then
			value = M.resolve_expr(item.expr, opts.state)
		end
		if value == nil then
			vim.notify("Invalid date: " .. tostring(item.expr), vim.log.levels.ERROR)
			return
		end
		callback(value)
	end)
end

function M.set_date_in_line(line, field, value)
	field = normalize_field(field or "due")
	local primary_symbol = FIELD_SYMBOLS[field]
	if not primary_symbol then
		return nil, "Unknown date field: " .. tostring(field)
	end
	local parsed = task_model.parse_line({
		line = line,
		global_filter = "",
	})
	if not parsed then
		return nil, "Line is not a task"
	end

	value = trim(value)
	if parsed.task_format == "dataview" or task_model.is_dataview_format() then
		local updated_body = task_model.set_dataview_date(parsed.body or "", field, value)
		local prefix = string.format("%s%s [%s]", parsed.indentation or "", parsed.list_marker or "-", parsed.status_symbol or " ")
		if updated_body == "" then
			return prefix
		end
		return prefix .. " " .. updated_body
	end

	for _, symbol in ipairs(task_model.DATE_SYMBOLS[field] or { primary_symbol }) do
		local pattern = symbol .. "%s*%d%d%d%d%-%d%d%-%d%d"
		if line:find(symbol, 1, true) then
			if value == "" then
				return rstrip(line:gsub("%s*" .. pattern, "", 1))
			end
			return line:gsub(pattern, symbol .. " " .. value, 1)
		end
	end

	if value == "" then
		return line
	end
	return rstrip(line) .. " " .. primary_symbol .. " " .. value
end

function M.set_date_at_cursor(field, value, opts)
	opts = opts or {}
	local buf = opts.buf or opts.buffer or vim.api.nvim_get_current_buf()
	local rejected = require("obsidian-tasks.core").reject_board_buffer_action(buf)
	if rejected ~= nil then
		return rejected
	end

	local row = opts.row or vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	local updated, err = M.set_date_in_line(line, field, value)
	if not updated then
		vim.notify(err, vim.log.levels.ERROR)
		return false
	end
	if updated ~= line then
		vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { updated })
		vim.api.nvim_set_option_value("modified", true, { buf = buf })
	end
	return true
end

function M.pick_at_cursor(opts)
	opts = opts or {}
	local field = normalize_field(opts.field or "due")
	local buf = opts.buf or opts.buffer or vim.api.nvim_get_current_buf()
	local rejected = require("obsidian-tasks.core").reject_board_buffer_action(buf)
	if rejected ~= nil then
		return rejected
	end

	local row = opts.row or vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	M.pick({
		prompt = field .. " date",
		state = opts.state,
		field = field,
		current_value = opts.current_value or M.date_in_line(line, field),
		calendar = opts.calendar,
		style = opts.style,
	}, function(value)
		local set_opts = vim.tbl_extend("force", opts, {
			buf = buf,
			row = row,
		})
		M.set_date_at_cursor(field, value, set_opts)
	end)
end

local function form_field_value(buf, field)
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local value = line:match("^" .. field .. ":%s*(.*)$")
		if value ~= nil then
			return trim(value)
		end
	end
	return nil
end

function M.pick_for_form(buf, field, opts)
	opts = opts or {}
	buf = buf or vim.api.nvim_get_current_buf()
	field = normalize_field(field or "due")
	return M.pick({
		prompt = field .. " date",
		state = opts.state,
		field = field,
		current_value = opts.current_value or form_field_value(buf, field),
		calendar = opts.calendar,
		style = opts.style,
	}, function(value)
		if opts.on_select then
			opts.on_select(value)
		end
	end)
end

return M
