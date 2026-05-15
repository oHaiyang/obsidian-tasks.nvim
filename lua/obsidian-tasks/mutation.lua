local M = {}

local date = require("obsidian-tasks.date")
local recurrence = require("obsidian-tasks.recurrence")
local status = require("obsidian-tasks.status")
local task_model = require("obsidian-tasks.task")

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function get_config()
	local ok, plugin = pcall(require, "obsidian-tasks")
	if ok and plugin then
		return plugin.config or {}
	end
	return {}
end

local function option(opts, snake, camel, default)
	opts = opts or {}
	local config = get_config()
	if opts[snake] ~= nil then
		return opts[snake]
	end
	if camel and opts[camel] ~= nil then
		return opts[camel]
	end
	if config[snake] ~= nil then
		return config[snake]
	end
	if camel and config[camel] ~= nil then
		return config[camel]
	end
	return default
end

local function field_symbol(field)
	local symbols = task_model.DATE_SYMBOLS[field] or {}
	return symbols[1]
end

local function remove_date(body, field)
	for _, symbol in ipairs(task_model.DATE_SYMBOLS[field] or {}) do
		body = body:gsub("%s*" .. symbol .. "%s*%d%d%d%d%-%d%d%-%d%d", "")
	end
	return trim(body)
end

local function replace_date(body, field, value)
	for _, symbol in ipairs(task_model.DATE_SYMBOLS[field] or {}) do
		local pattern = "(" .. symbol .. "%s*)%d%d%d%d%-%d%d%-%d%d"
		local updated, count = body:gsub(pattern, "%1" .. value, 1)
		if count > 0 then
			return trim(updated), true
		end
	end
	return trim(body), false
end

local function append_metadata(body, metadata)
	body = trim(body)
	local before, block_link = body:match("^(.-)%s+(%^[%w%-]+)%s*$")
	if block_link then
		return trim(trim(before) .. " " .. metadata .. " " .. block_link)
	end
	return trim(body .. " " .. metadata)
end

local function replace_or_append_date(body, field, value)
	local updated, replaced = replace_date(body, field, value)
	if replaced then
		return updated
	end
	return append_metadata(updated, (field_symbol(field) or "") .. " " .. value)
end

local function set_date_field(task, field, value)
	task.dates = task.dates or {}
	task.dates[field] = value
	task[field .. "_date"] = value
end

function M.change_status(task, next_symbol, opts)
	opts = opts or {}
	next_symbol = status.normalize_symbol(next_symbol)
	local status_config = vim.tbl_extend("force", get_config(), opts)

	local old_type = status.type(task.status_symbol or task.status, status_config)
	local new_type = status.type(next_symbol, status_config)
	local body = task.body or task.display_text or task.text or ""
	local updated = status.with_status(task, next_symbol)

	if new_type ~= "DONE" then
		body = remove_date(body, "done")
		set_date_field(updated, "done", nil)
	end
	if new_type ~= "CANCELLED" then
		body = remove_date(body, "cancelled")
		set_date_field(updated, "cancelled", nil)
	end

	if new_type == "DONE" and old_type ~= "DONE" and option(opts, "set_done_date", "setDoneDate", false) then
		local today = opts.today or date.today()
		body = replace_or_append_date(body, "done", today)
		set_date_field(updated, "done", today)
	end

	if
		new_type == "CANCELLED"
		and old_type ~= "CANCELLED"
		and option(opts, "set_cancelled_date", "setCancelledDate", false)
	then
		local today = opts.today or date.today()
		body = replace_or_append_date(body, "cancelled", today)
		set_date_field(updated, "cancelled", today)
	end

	updated.body = trim(body)
	updated.display_text = updated.body
	updated.text = updated.body
	return updated
end

function M.toggle_status(task, opts)
	local next_symbol = status.next_symbol(task.status_symbol or task.status, vim.tbl_extend("force", get_config(), opts or {}))
	return M.change_status(task, next_symbol, opts)
end

local function recurrence_opts(opts)
	opts = opts or {}
	return {
		today = opts.today,
		recurrence_on_next_line = option(opts, "recurrence_on_next_line", "recurrenceOnNextLine", false),
		remove_scheduled_date_on_recurrence = option(
			opts,
			"remove_scheduled_date_on_recurrence",
			"removeScheduledDateOnRecurrence",
			false
		),
		set_created_date = option(opts, "set_created_date", "setCreatedDate", false),
	}
end

function M.apply_status_change_to_lines(lines, line_number, next_symbol, opts)
	opts = opts or {}
	local line = lines[line_number]
	if not line then
		return false, "Line not found"
	end

	local task = task_model.parse_line({
		line = line,
		file_path = opts.file_path,
		line_number = line_number,
		global_filter = "",
	})
	if not task then
		return false, "Line is no longer a valid task"
	end

	local status_config = vim.tbl_extend("force", get_config(), opts)
	local old_type = status.type(task.status_symbol, status_config)
	local updated = M.change_status(task, next_symbol, opts)
	local new_type = status.type(updated.status_symbol, status_config)
	local replacement = { task_model.serialize(updated) }

	if old_type ~= "DONE" and new_type == "DONE" and task.is_recurring then
		local next_task = recurrence.next_task(updated, recurrence_opts(opts))
		if next_task then
			local next_line = task_model.serialize(next_task)
			if recurrence.should_delete_completed(updated) then
				replacement = { next_line }
			elseif option(opts, "recurrence_on_next_line", "recurrenceOnNextLine", false) then
				replacement = { task_model.serialize(updated), next_line }
			else
				replacement = { next_line, task_model.serialize(updated) }
			end
		end
	end

	local new_lines = vim.deepcopy(lines)
	table.remove(new_lines, line_number)
	for offset, replacement_line in ipairs(replacement) do
		table.insert(new_lines, line_number + offset - 1, replacement_line)
	end

	return true, new_lines, updated
end

local function default_postpone_target(current, opts)
	local today = opts.today or date.today()
	if current <= today then
		return date.add_days(today, 1)
	end
	return date.add_days(current, 1)
end

local function parse_postpone_expr(expr, current, opts)
	expr = trim(expr)
	if expr == "" then
		return default_postpone_target(current, opts)
	end

	local amount = expr:match("^%+(%d+)$") or expr:match("^(%d+)%s+days?$")
	if amount then
		return date.add_days(current, tonumber(amount))
	end

	return date.parse_date_expr(expr, opts)
end

function M.postpone_task(task, expr, opts)
	opts = opts or {}
	local field
	local current
	for _, candidate in ipairs({ "due", "scheduled", "start" }) do
		local value = task[candidate .. "_date"]
		if date.is_valid(value) then
			field = candidate
			current = value
			break
		end
	end

	if not field then
		return nil, "Task has no due, scheduled, or start date"
	end

	local target = parse_postpone_expr(expr, current, opts)
	if not date.is_valid(target) then
		return nil, "Invalid postpone date"
	end

	local updated = {}
	for key, value in pairs(task) do
		updated[key] = value
	end
	updated.body = replace_or_append_date(updated.body or updated.display_text or updated.text or "", field, target)
	updated.display_text = updated.body
	updated.text = updated.body
	set_date_field(updated, field, target)
	return updated, nil, field, target
end

function M.apply_postpone_to_lines(lines, line_number, expr, opts)
	opts = opts or {}
	local line = lines[line_number]
	if not line then
		return false, "Line not found"
	end

	local task = task_model.parse_line({
		line = line,
		file_path = opts.file_path,
		line_number = line_number,
		global_filter = "",
	})
	if not task then
		return false, "Line is no longer a valid task"
	end

	local updated, err, field, target = M.postpone_task(task, expr, opts)
	if not updated then
		return false, err
	end

	local new_lines = vim.deepcopy(lines)
	new_lines[line_number] = task_model.serialize(updated)
	return true, new_lines, updated, field, target
end

return M
