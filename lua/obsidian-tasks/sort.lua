local M = {}

local date = require("obsidian-tasks.date")
local status = require("obsidian-tasks.status")

M.PRIORITY_ORDER = {
	highest = 1,
	high = 2,
	medium = 3,
	normal = 4,
	none = 4,
	low = 5,
	lowest = 6,
}

local function is_done(task)
	return status.is_complete_symbol(task.status_symbol or task.status)
end

local function filename_without_extension(task)
	if task.file and task.file.filename_without_extension then
		return task.file.filename_without_extension
	end
	local filename = (task.file_path or ""):match("([^/]+)$") or ""
	return filename:gsub("%.[^%.]+$", "")
end

local function value_for(task, field)
	field = (field or ""):lower()

	if field == "priority" then
		return M.PRIORITY_ORDER[task.priority or "normal"] or M.PRIORITY_ORDER.normal
	elseif field == "status" then
		return is_done(task) and 1 or 0
	elseif field == "status.type" then
		return status.type(task.status_symbol or task.status)
	elseif field == "description" then
		return task.description or task.text or ""
	elseif field == "path" then
		return task.file_path or ""
	elseif field == "file" or field == "filename" then
		return filename_without_extension(task)
	elseif field == "heading" then
		return task.heading or ""
	elseif field == "urgency" then
		-- Obsidian Tasks sorts urgency from highest to lowest by default.
		return -(tonumber(task.urgency) or 0)
	elseif date.normalize_field(field) then
		return date.get_task_date(task, field)
	end

	return task[field]
end

local function compare_values(left, right, reverse)
	if left == nil or left == "" then
		if right == nil or right == "" then
			return nil
		end
		return false
	elseif right == nil or right == "" then
		return true
	end

	if left == right then
		return nil
	end

	if reverse then
		return left > right
	end
	return left < right
end

function M.apply(tasks, sorts)
	local sorted = {}
	for index, task in ipairs(tasks or {}) do
		task.__obsidian_tasks_order = task.__obsidian_tasks_order or index
		table.insert(sorted, task)
	end

	if not sorts or #sorts == 0 then
		return sorted
	end

	table.sort(sorted, function(left, right)
		for _, spec in ipairs(sorts) do
			local result = compare_values(value_for(left, spec.field), value_for(right, spec.field), spec.reverse)
			if result ~= nil then
				return result
			end
		end
		return (left.__obsidian_tasks_order or 0) < (right.__obsidian_tasks_order or 0)
	end)

	for _, task in ipairs(sorted) do
		task.__obsidian_tasks_order = nil
	end

	return sorted
end

return M
