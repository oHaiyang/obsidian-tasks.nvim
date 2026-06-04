local M = {}

local date = require("obsidian-tasks.date")
local status = require("obsidian-tasks.status")
local task_model = require("obsidian-tasks.task")

local DATE_FIELDS = { "start", "scheduled", "due" }
local ALL_DATE_FIELDS = { "created", "start", "scheduled", "due", "done", "cancelled" }

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local WEEKDAYS = {
	sun = 0,
	sunday = 0,
	mon = 1,
	monday = 1,
	tue = 2,
	tues = 2,
	tuesday = 2,
	wed = 3,
	wednesday = 3,
	thu = 4,
	thur = 4,
	thurs = 4,
	thursday = 4,
	fri = 5,
	friday = 5,
	sat = 6,
	saturday = 6,
}

local WEEKDAY_SET = {
	weekday = { 1, 2, 3, 4, 5 },
	weekdays = { 1, 2, 3, 4, 5 },
	weekend = { 0, 6 },
	weekends = { 0, 6 },
}

local function parse_ymd(value)
	local year, month, day = tostring(value or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not year then
		return nil
	end
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
	while month > 12 do
		year = year + 1
		month = month - 12
	end
	while month < 1 do
		year = year - 1
		month = month + 12
	end

	day = math.min(day, days_in_month(year, month))
	return string.format("%04d-%02d-%02d", year, month, day)
end

local function weekday(value)
	if not date.is_valid(value) then
		return nil
	end
	local year, month, day = parse_ymd(value)
	return tonumber(os.date("%w", os.time({
		year = year,
		month = month,
		day = day,
		hour = 12,
		min = 0,
		sec = 0,
	})))
end

local function contains_weekday(weekdays, value)
	for _, weekday_value in ipairs(weekdays or {}) do
		if weekday_value == value then
			return true
		end
	end
	return false
end

local function normalize_rule(rule)
	rule = trim(rule):lower()
	rule = rule:gsub("%s+", " ")
	local when_done = rule:find("when done", 1, true) ~= nil
	rule = trim(rule:gsub("%s*when done%s*$", ""))

	local strict = false
	if rule:match("^every!") then
		strict = true
		rule = trim(rule:gsub("^every!%s*", "every ", 1))
	end

	return rule, when_done, strict
end

local function with_common(interval, when_done, strict)
	interval.when_done = when_done
	interval.strict = strict
	return interval
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

function M.parse_rule(rule)
	local when_done, strict
	rule, when_done, strict = normalize_rule(rule)
	if rule == "" then
		return nil
	end

	local count, unit
	local weekday_name

	count, weekday_name = rule:match("^every%s+(%d+)%s+weeks?%s+on%s+([%a]+)$")
	if count and WEEKDAYS[weekday_name] ~= nil then
		return with_common({
			kind = "weekday",
			count = tonumber(count),
			unit = "week",
			weekday = WEEKDAYS[weekday_name],
		}, when_done, strict)
	end

	weekday_name = rule:match("^every%s+week%s+on%s+([%a]+)$")
	if weekday_name and WEEKDAYS[weekday_name] ~= nil then
		return with_common({
			kind = "weekday",
			count = 1,
			unit = "week",
			weekday = WEEKDAYS[weekday_name],
		}, when_done, strict)
	end

	weekday_name = rule:match("^every%s+other%s+([%a]+)$")
	if weekday_name and WEEKDAYS[weekday_name] ~= nil then
		return with_common({
			kind = "weekday",
			count = 2,
			unit = "week",
			weekday = WEEKDAYS[weekday_name],
		}, when_done, strict)
	end

	weekday_name = rule:match("^every%s+([%a]+)$")
	if weekday_name and WEEKDAYS[weekday_name] ~= nil then
		return with_common({
			kind = "weekday",
			count = 1,
			unit = "week",
			weekday = WEEKDAYS[weekday_name],
		}, when_done, strict)
	end

	local weekday_set = WEEKDAY_SET[weekday_name]
	if weekday_set then
		return with_common({
			kind = "weekday_set",
			count = 1,
			unit = "day",
			weekdays = weekday_set,
		}, when_done, strict)
	end

	local day
	count, day = rule:match("^every%s+(%d+)%s+months?%s+on%s+the%s+(%d+)%a*$")
	if not count then
		count, day = rule:match("^every%s+(%d+)%s+months?%s+on%s+(%d+)%a*$")
	end
	if count and day then
		return with_common({
			kind = "monthday",
			count = tonumber(count),
			unit = "month",
			day = tonumber(day),
		}, when_done, strict)
	end

	day = rule:match("^every%s+month%s+on%s+the%s+(%d+)%a*$") or rule:match("^every%s+month%s+on%s+(%d+)%a*$")
	if day then
		return with_common({
			kind = "monthday",
			count = 1,
			unit = "month",
			day = tonumber(day),
		}, when_done, strict)
	end

	day = rule:match("^every%s+other%s+month%s+on%s+the%s+(%d+)%a*$")
		or rule:match("^every%s+other%s+month%s+on%s+(%d+)%a*$")
	if day then
		return with_common({
			kind = "monthday",
			count = 2,
			unit = "month",
			day = tonumber(day),
		}, when_done, strict)
	end

	count, unit = rule:match("^every%s+(%d+)%s+(day)s?$")
	if not count then
		count, unit = rule:match("^every%s+(%d+)%s+(week)s?$")
	end
	if not count then
		count, unit = rule:match("^every%s+(%d+)%s+(month)s?$")
	end
	if not count then
		count, unit = rule:match("^every%s+(%d+)%s+(year)s?$")
	end
	if count and unit then
		return with_common({
			count = tonumber(count),
			unit = unit,
		}, when_done, strict)
	end

	unit = rule:match("^every%s+(day)$")
		or rule:match("^every%s+(week)$")
		or rule:match("^every%s+(month)$")
		or rule:match("^every%s+(year)$")
	if unit then
		return with_common({
			count = 1,
			unit = unit,
		}, when_done, strict)
	end

	unit = rule:match("^every%s+other%s+(day)$")
		or rule:match("^every%s+other%s+(week)$")
		or rule:match("^every%s+other%s+(month)$")
		or rule:match("^every%s+other%s+(year)$")
	if unit then
		return with_common({
			count = 2,
			unit = unit,
		}, when_done, strict)
	end

	return nil
end

local function advance_to_weekday(value, target, count)
	local current = weekday(value)
	if current == nil then
		return nil
	end

	local delta = target - current
	if delta <= 0 then
		delta = delta + 7
	end

	return date.add_days(value, delta + ((count or 1) - 1) * 7)
end

local function advance_to_weekday_set(value, weekdays)
	for offset = 1, 7 do
		local candidate = date.add_days(value, offset)
		if contains_weekday(weekdays, weekday(candidate)) then
			return candidate
		end
	end
	return nil
end

local function advance_to_monthday(value, target_day, count)
	target_day = tonumber(target_day)
	if not target_day or target_day < 1 or target_day > 31 then
		return nil
	end

	local year, month = parse_ymd(value)
	if not year then
		return nil
	end

	local candidate = make_date(year, month, target_day)
	if candidate <= value then
		candidate = make_date(year, month + (count or 1), target_day)
	end
	return candidate
end

function M.advance_date(value, interval, base)
	if not interval then
		return nil
	end
	value = interval.when_done and base or value
	if not date.is_valid(value) then
		return nil
	end

	if interval.kind == "weekday" then
		return advance_to_weekday(value, interval.weekday, interval.count)
	elseif interval.kind == "weekday_set" then
		return advance_to_weekday_set(value, interval.weekdays)
	elseif interval.kind == "monthday" then
		return advance_to_monthday(value, interval.day, interval.count)
	elseif interval.unit == "day" then
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

	local interval = M.parse_rule(task.recurrence_rule)
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
	local next_dates = {}

	for key, value in pairs(task.dates or {}) do
		if key ~= "done" and key ~= "cancelled" then
			next_dates[key] = value
		end
	end

	for _, field in ipairs(DATE_FIELDS) do
		local current = task[field .. "_date"]
		local next_value = M.advance_date(current, interval, base)
		if next_value then
			body = replace_date(body, field, next_value, task)
			next_dates[field] = next_value
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
			next_dates.scheduled = nil
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
		next_dates.created = today
	end

	local next_task = status.with_status(task, opts.next_status_symbol or opts.nextStatusSymbol or " ")
	next_task.body = trim(body)
	next_task.display_text = next_task.body
	next_task.text = next_task.body
	next_task.dates = next_dates
	for _, field in ipairs(ALL_DATE_FIELDS) do
		next_task[field .. "_date"] = next_dates[field]
	end
	return next_task
end

function M.should_delete_completed(task)
	return trim(task and task.on_completion or "") == "delete"
end

return M
