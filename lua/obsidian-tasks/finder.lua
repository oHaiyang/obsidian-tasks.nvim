local M = {}

local parser = require("obsidian-tasks.parser")
local display = require("obsidian-tasks.display")
local scanner = require("obsidian-tasks.scanner")

local function normalize_filter(filter)
	if type(filter) == "function" then
		return {
			custom = filter,
		}
	end

	if type(filter) ~= "table" then
		filter = {}
	end

	filter.custom = filter.custom or function()
		return true
	end

	return filter
end

local function status_matches(task, status)
	if task.status == status or task.status_symbol == status then
		return true
	end
	if type(status) == "string" and #status == 1 then
		return task.status == "[" .. status .. "]"
	end
	return false
end

local function apply_filter_options(tasks, filter)
	local filtered = {}

	for _, task in ipairs(tasks) do
		local include_task = true

		if filter.include_files and #filter.include_files > 0 then
			include_task = false
			for _, pattern in ipairs(filter.include_files) do
				if task.file_path and task.file_path:match(pattern) then
					include_task = true
					break
				end
			end
		end

		if include_task and filter.exclude_files and #filter.exclude_files > 0 then
			for _, pattern in ipairs(filter.exclude_files) do
				if task.file_path and task.file_path:match(pattern) then
					include_task = false
					break
				end
			end
		end

		if include_task and filter.status then
			local status_filters = filter.status
			if type(status_filters) == "string" then
				status_filters = { status_filters }
			end

			include_task = false
			for _, status in ipairs(status_filters) do
				if status_matches(task, status) then
					include_task = true
					break
				end
			end
		end

		if include_task then
			table.insert(filtered, task)
		end
	end

	return parser.filter_tasks(filtered, filter.custom)
end

-- Main function to find tasks.
---@param opts? ObsidianTaskFinderOptions
---@return nil
function M.find_tasks(opts)
	opts = opts or {}

	local filter = normalize_filter(opts.filter or {})
	local group_by = opts.group_by or {}
	local use_float = opts.float or false
	local vault_path = opts.vault_path
	local global_filter = opts.global_filter or opts.globalFilter or ""
	local display_opts = {
		hierarchical_headings = opts.hierarchical_headings or false,
	}

	display.last_finder_opts = {
		filter = filter,
		group_by = group_by,
		float = use_float,
		vault_path = vault_path,
		global_filter = global_filter,
		hierarchical_headings = opts.hierarchical_headings or false,
	}

	M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by, display_opts, global_filter)
end

-- Compatibility wrapper. The original implementation used ripgrep directly;
-- the Task Core MVP scans markdown files so parser semantics stay in one place.
---@param vault_path string
---@param filter ObsidianTaskFilter
---@param use_float boolean
---@param group_by table
---@param display_opts ObsidianTaskDisplayOptions
---@param global_filter? string
---@return nil
function M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by, display_opts, global_filter)
	if not vault_path or vault_path == "" then
		vim.notify("obsidian-tasks.nvim: vault_path is required", vim.log.levels.ERROR)
		return
	end

	local tasks = scanner.scan_vault({
		vault_path = vault_path,
		global_filter = global_filter or "",
	})

	local filtered_tasks = apply_filter_options(tasks, filter)

	if #filtered_tasks == 0 then
		vim.notify("No tasks found in the vault.", vim.log.levels.INFO)
		return
	end

	local grouped_tasks, group_order = parser.group_tasks(filtered_tasks, group_by or {})
	if use_float then
		display.display_tasks_float(filtered_tasks, grouped_tasks, group_order, display_opts)
	else
		display.display_tasks(filtered_tasks, grouped_tasks, group_order, display_opts)
	end
end

return M
