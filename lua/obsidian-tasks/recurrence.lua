local M = {}

local date = require("obsidian-tasks.date")
local status = require("obsidian-tasks.status")
local task_model = require("obsidian-tasks.task")

local DATE_FIELDS = { "start", "scheduled", "due" }

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function field_symbols(field)
	return task_model.DATE_SYMBOLS[field] or {}
end

local function is_dataview_task(task)
	return task and (task.task_format == "dataview" or task.taskFormat == "dataview")
end

local function has_dataview_date(body, field)
	local key = task_model.DATAVIEW_DATE_KEYS[field]
	return key and task_model.dataview_field_value(body, key) ~= nil
end

local function remove_date(body, field, task)
	if is_dataview_task(task) then
		return task_model.set_dataview_date(body, field, "")
	end
	for _, symbol in ipairs(field_symbols(field)) do
		body = body:gsub("%s*" .. symbol .. "%s*%d%d%d%d%-%d%d%-%d%d", "")
	end
	return trim(body)
end

local function replace_date(body, field, value, task)
	if is_dataview_task(task) then
		if not has_dataview_date(body, field) then
			return trim(body), false
		end
		return task_model.set_dataview_date(body, field, value), true
	end
	for _, symbol in ipairs(field_symbols(field)) do
		local pattern = "(" .. symbol .. "%s*)%d%d%d%d%-%d%d%-%d%d"
		local updated, count = body:gsub(pattern, "%1" .. value, 1)
		if count > 0 then
			return trim(updated), true
		end
	end
	return trim(body), false
end

local function remove_task_id(body, task)
	if is_dataview_task(task) then
		return task_model.set_dataview_metadata(body, "id", "")
	end
	return trim((body or ""):gsub("%s*🆔%s*[%w_%-]+", ""))
end

local function remove_depends_on(body, task)
	if is_dataview_task(task) then
		return task_model.set_dataview_metadata(body, "depends_on", "")
	end
	return trim((body or ""):gsub("%s*⛔%s*[%w_%-,%s]+", ""))
end

local function parse_rule(rule)
	rule = trim(rule):lower()
	if rule == "" then
		return nil
	end

	local count, unit = rule:match("^every%s+(%d+)%s+(day)s?")
	if not count then
		count, unit = rule:match("^every%s+(%d+)%s+(week)s?")
	end
	if not count then
		count, unit = rule:match("^every%s+(%d+)%s+(month)s?")
	end
	if not count then
		count, unit = rule:match("^every%s+(%d+)%s+(year)s?")
	end
	if count and unit then
		return {
			count = tonumber(count),
			unit = unit,
			when_done = rule:find("when done", 1, true) ~= nil,
		}
	end

	unit = rule:match("^every%s+(day)") or rule:match("^every%s+(week)") or rule:match("^every%s+(month)") or rule:match("^every%s+(year)")
	if unit then
		return {
			count = 1,
			unit = unit,
			when_done = rule:find("when done", 1, true) ~= nil,
		}
	end

	unit = rule:match("^every%s+other%s+(day)") or rule:match("^every%s+other%s+(week)") or rule:match("^every%s+other%s+(month)") or rule:match("^every%s+other%s+(year)")
	if unit then
		return {
			count = 2,
			unit = unit,
			when_done = rule:find("when done", 1, true) ~= nil,
		}
	end

	return nil
end

function M.advance_date(value, interval, base)
	if not interval then
		return nil
	end
	value = interval.when_done and base or value
	if not date.is_valid(value) then
		return nil
	end

	if interval.unit == "day" then
		return date.add_days(value, interval.count)
	elseif interval.unit == "week" then
		return date.add_days(value, interval.count * 7)
	elseif interval.unit == "month" then
		return date.add_months(value, interval.count)
	elseif interval.unit == "year" then
		return date.add_months(value, interval.count * 12)
	end
	return nil
end

function M.next_task(task, opts)
	opts = opts or {}
	if not task or not task.is_recurring or trim(task.recurrence_rule) == "" then
		return nil
	end

	local interval = parse_rule(task.recurrence_rule)
	if not interval then
		return nil
	end

	local body = task.body or task.display_text or task.text or ""
	body = remove_date(body, "done", task)
	body = remove_date(body, "cancelled", task)
	body = remove_task_id(body, task)
	body = remove_depends_on(body, task)

	local advanced_any = false
	local base = task.done_date or opts.today or date.today()
	local has_start_or_due = false

	for _, field in ipairs(DATE_FIELDS) do
		local current = task[field .. "_date"]
		local next_value = M.advance_date(current, interval, base)
		if next_value then
			body = replace_date(body, field, next_value, task)
			advanced_any = true
			if field == "start" or field == "due" then
				has_start_or_due = true
			end
		end
	end

	if not advanced_any then
		return nil
	end

	if opts.remove_scheduled_date_on_recurrence or opts.removeScheduledDateOnRecurrence then
		if has_start_or_due then
			body = remove_date(body, "scheduled", task)
		end
	end

	if opts.set_created_date or opts.setCreatedDate then
		local today = opts.today or date.today()
		local replaced
		body, replaced = replace_date(body, "created", today, task)
		if not replaced then
			if is_dataview_task(task) then
				body = task_model.set_dataview_date(body, "created", today)
			else
				body = trim(body .. " " .. (field_symbols("created")[1] or "➕") .. " " .. today)
			end
		end
	end

	local next_task = status.with_status(task, opts.next_status_symbol or opts.nextStatusSymbol or " ")
	next_task.body = trim(body)
	next_task.display_text = next_task.body
	next_task.text = next_task.body
	return next_task
end

function M.should_delete_completed(task)
	return trim(task and task.on_completion or "") == "delete"
end

return M
