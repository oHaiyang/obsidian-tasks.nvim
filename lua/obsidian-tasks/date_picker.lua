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

local function normalize_field(field)
	field = trim(field):lower():gsub("_", " ")
	return FIELD_ALIASES[field] or field:gsub("%s+", "_")
end

local function date_opts(state)
	return {
		today = (state and state.today) or get_config().today,
	}
end

function M.choices()
	return {
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
end

function M.resolve_expr(expr, state)
	if expr == "" then
		return ""
	end
	return date.parse_date_expr(expr, date_opts(state))
end

function M.pick(opts, callback)
	opts = opts or {}
	vim.ui.select(M.choices(), {
		prompt = opts.prompt or "Task date",
		format_item = function(item)
			return item.label
		end,
	}, function(item)
		if not item then
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
	local symbol = FIELD_SYMBOLS[field]
	if not symbol then
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
	local pattern = symbol .. "%s*%d%d%d%d%-%d%d%-%d%d"
	if line:find(symbol, 1, true) then
		if value == "" then
			return rstrip(line:gsub("%s*" .. pattern, "", 1))
		end
		return line:gsub(pattern, symbol .. " " .. value, 1)
	end

	if value == "" then
		return line
	end
	return rstrip(line) .. " " .. symbol .. " " .. value
end

function M.set_date_at_cursor(field, value, opts)
	opts = opts or {}
	local buf = opts.buf or opts.buffer or vim.api.nvim_get_current_buf()
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
	M.pick({
		prompt = field .. " date",
		state = opts.state,
	}, function(value)
		M.set_date_at_cursor(field, value, opts)
	end)
end

return M
