local M = {}

local date = require("obsidian-tasks.date")

local DUE_COEFFICIENT = 12.0
local SCHEDULED_COEFFICIENT = 5.0
local STARTED_COEFFICIENT = -3.0
local PRIORITY_COEFFICIENT = 6.0

local PRIORITY_MULTIPLIERS = {
	highest = 1.5,
	high = 1.0,
	medium = 0.65,
	normal = 0.325,
	none = 0.325,
	low = 0.0,
	lowest = -0.3,
}

local function today(opts)
	opts = opts or {}
	if opts.today then
		return opts.today
	end
	local ok, plugin = pcall(require, "obsidian-tasks")
	if ok and plugin.config and plugin.config.today then
		return plugin.config.today
	end
	return date.today()
end

local function priority_score(priority)
	local multiplier = PRIORITY_MULTIPLIERS[(priority or "normal"):lower()] or PRIORITY_MULTIPLIERS.normal
	return multiplier * PRIORITY_COEFFICIENT
end

local function due_score(task, today_value)
	local due = task.due_date
	if not date.is_valid(due) then
		return 0.0
	end

	local days_overdue = date.days_between(today_value, due)
	if days_overdue == nil then
		return 0.0
	end

	local multiplier
	if days_overdue >= 7.0 then
		multiplier = 1.0
	elseif days_overdue >= -14.0 then
		multiplier = ((days_overdue + 14.0) * 0.8) / 21.0 + 0.2
	else
		multiplier = 0.2
	end

	return multiplier * DUE_COEFFICIENT
end

local function scheduled_score(task, today_value)
	local scheduled = task.scheduled_date
	if date.is_valid(scheduled) and scheduled <= today_value then
		return SCHEDULED_COEFFICIENT
	end
	return 0.0
end

local function start_score(task, today_value)
	local start = task.start_date
	if date.is_valid(start) and start > today_value then
		return STARTED_COEFFICIENT
	end
	return 0.0
end

function M.score(task, opts)
	local today_value = today(opts)
	if not date.is_valid(today_value) then
		today_value = date.today()
	end

	return due_score(task, today_value)
		+ priority_score(task.priority)
		+ scheduled_score(task, today_value)
		+ start_score(task, today_value)
end

function M.enrich(task, opts)
	task.urgency = M.score(task, opts)
	return task
end

function M.format(task)
	return string.format("%.2f", tonumber(task and task.urgency) or 0)
end

return M
