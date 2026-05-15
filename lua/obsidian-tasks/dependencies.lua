local M = {}

local status = require("obsidian-tasks.status")

local function has_value(list, value)
	for _, item in ipairs(list or {}) do
		if item == value then
			return true
		end
	end
	return false
end

local function is_incomplete(task, opts)
	return status.is_incomplete_symbol(task.status_symbol or task.status, opts)
end

function M.incomplete_id_map(tasks, opts)
	local map = {}
	for _, task in ipairs(tasks or {}) do
		if (task.id or "") ~= "" and is_incomplete(task, opts) then
			map[task.id] = task
		end
	end
	return map
end

function M.is_blocked(task, tasks, opts)
	local depends_on = task.depends_on or task.dependsOn or {}
	if #depends_on == 0 then
		return false
	end

	local incomplete_ids = M.incomplete_id_map(tasks, opts)
	for _, id in ipairs(depends_on) do
		if incomplete_ids[id] then
			return true
		end
	end
	return false
end

function M.is_blocking(task, tasks, opts)
	local id = task.id or ""
	if id == "" or not is_incomplete(task, opts) then
		return false
	end

	for _, other in ipairs(tasks or {}) do
		if other ~= task and is_incomplete(other, opts) and has_value(other.depends_on or other.dependsOn or {}, id) then
			return true
		end
	end
	return false
end

return M
