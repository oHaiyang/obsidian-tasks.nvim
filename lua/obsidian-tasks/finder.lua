local M = {}

local parser = require("obsidian-tasks.parser")
local cache = require("obsidian-tasks.cache")
local display = require("obsidian-tasks.display")
local query = require("obsidian-tasks.query")
local sorter = require("obsidian-tasks.sort")

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

local function apply_limit(tasks, limit)
	if not limit or limit <= 0 or #tasks <= limit then
		return tasks
	end

	local limited = {}
	for index = 1, limit do
		table.insert(limited, tasks[index])
	end
	return limited
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
	local query_text = opts.query
	local query_plan = nil
	local composition = nil

	if query_text and query_text ~= "" then
		local query_opts = {
			today = opts.today,
			config = require("obsidian-tasks").config or {},
			enable_lua_filters = opts.enable_lua_filters or opts.enableLuaFilters,
			query_source = opts.query_source,
			query_file_path = opts.query_file_path or opts.queryFilePath,
			source_path = opts.source_path or opts.sourcePath,
		}
		composition = query.compose(query_text, query_opts)
		query_plan = query.parse(composition.source, query_opts)
		query_plan.composition = composition
		query_plan.original_query = query_text
		if #query_plan.errors > 0 then
			display.last_finder_opts = {
				filter = filter,
				group_by = group_by,
				float = use_float,
				vault_path = vault_path,
				global_filter = global_filter,
				hierarchical_headings = opts.hierarchical_headings or false,
				query = query_text,
				query_name = opts.query_name,
				query_source = opts.query_source,
				query_file_path = opts.query_file_path or opts.queryFilePath,
				source_path = opts.source_path or opts.sourcePath,
				buffer_name = opts.buffer_name,
				reuse_buffer = opts.reuse_buffer,
				pinned = opts.pinned,
				today = opts.today,
				toolbar_filter = opts.toolbar_filter,
				use_cache = opts.use_cache or opts.useCache,
				composition = composition,
			}
			local error_opts = {
				query_name = opts.query_name,
				query_source = opts.query_source,
				composition = composition,
				buffer_name = opts.buffer_name,
				reuse_buffer = opts.reuse_buffer,
				float = use_float,
				finder_opts = display.last_finder_opts,
			}
			display.display_query_errors(query_plan.errors, error_opts)
			return
		end

		if #query_plan.group_by > 0 then
			group_by = query_plan.group_by
		end
	end

	local display_opts = {
		hierarchical_headings = opts.hierarchical_headings or false,
		query_name = opts.query_name,
		query_source = opts.query_source,
		query_plan = query_plan,
		layout = query_plan and query_plan.layout or nil,
		buffer_name = opts.buffer_name,
		reuse_buffer = opts.reuse_buffer,
		pinned = opts.pinned,
		composition = composition,
		today = opts.today,
		group_by = group_by,
		toolbar_filter = opts.toolbar_filter,
		use_cache = opts.use_cache or opts.useCache,
	}

	display.last_finder_opts = {
		filter = filter,
		group_by = group_by,
		float = use_float,
		vault_path = vault_path,
		global_filter = global_filter,
		hierarchical_headings = opts.hierarchical_headings or false,
		query = query_text,
		query_name = opts.query_name,
		query_source = opts.query_source,
		query_file_path = opts.query_file_path or opts.queryFilePath,
		source_path = opts.source_path or opts.sourcePath,
		buffer_name = opts.buffer_name,
		reuse_buffer = opts.reuse_buffer,
		pinned = opts.pinned,
		today = opts.today,
		toolbar_filter = opts.toolbar_filter,
		use_cache = opts.use_cache or opts.useCache,
		composition = composition,
	}
	display_opts.finder_opts = display.last_finder_opts

	M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by, display_opts, global_filter, query_plan)
end

-- Compatibility wrapper. The original implementation used ripgrep directly;
-- the Task Core MVP scans markdown files so parser semantics stay in one place.
---@param vault_path string
---@param filter ObsidianTaskFilter
---@param use_float boolean
---@param group_by table
---@param display_opts ObsidianTaskDisplayOptions
---@param global_filter? string
---@param query_plan? table
---@return nil
function M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by, display_opts, global_filter, query_plan)
	if not vault_path or vault_path == "" then
		vim.notify("obsidian-tasks.nvim: vault_path is required", vim.log.levels.ERROR)
		return
	end

	local tasks = cache.tasks({
		vault_path = vault_path,
		global_filter = global_filter or "",
		today = display_opts.today,
		use_cache = display_opts.use_cache,
	})

	local query_filtered_tasks = tasks
	if query_plan then
		query_filtered_tasks = query.filter_tasks(tasks, query_plan)
	end

	local filtered_tasks = apply_filter_options(query_filtered_tasks, filter)

	if query_plan and #query_plan.sorts > 0 then
		filtered_tasks = sorter.apply(filtered_tasks, query_plan.sorts)
	end

	local total_count = #filtered_tasks
	if query_plan and query_plan.limit then
		filtered_tasks = apply_limit(filtered_tasks, query_plan.limit)
	end

	display_opts.total_count = total_count
	display_opts.shown_count = #filtered_tasks
	display_opts.limit = query_plan and query_plan.limit or nil

	local grouped_tasks, group_order = parser.group_tasks(filtered_tasks, group_by or {})
	if use_float then
		display.display_tasks_float(filtered_tasks, grouped_tasks, group_order, display_opts)
	else
		display.display_tasks(filtered_tasks, grouped_tasks, group_order, display_opts)
	end
end

return M
