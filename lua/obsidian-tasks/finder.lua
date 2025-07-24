local M = {}

local parser = require("obsidian-tasks.parser")
local display = require("obsidian-tasks.display")
local core = require("obsidian-tasks.core")

-- Main function to find tasks
---@param opts? ObsidianTaskFinderOptions
---@return nil
function M.find_tasks(opts)
	opts = opts or {}
	local filter = opts.filter or {}

	-- 将 filter 从函数转换为对象（如果它是函数）
	if type(filter) == "function" then
		local filter_fn = filter
		filter = {
			custom = filter_fn,
		}
	else
		filter = filter or {}
		-- 确保 filter 是一个表
		if type(filter) ~= "table" then
			filter = {}
		end
	end

	-- 设置默认的自定义过滤器函数
	filter.custom = filter.custom or function()
		return true
	end

	local group_by = opts.group_by or {}
	local use_float = opts.float or false
	local vault_path = opts.vault_path
	local display_opts = {
		hierarchical_headings = opts.hierarchical_headings or false
	}

	-- Store the options for refresh functionality
	display.last_finder_opts = {
		filter = filter,
		group_by = group_by,
		float = use_float,
		vault_path = vault_path,
		hierarchical_headings = opts.hierarchical_headings or false
	}

	-- Call ripgrep to find tasks
	M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by, display_opts)
end

-- Find tasks using vim.loop and ripgrep
---@param vault_path string # Path to the Obsidian vault
---@param filter ObsidianTaskFilter # Filter criteria for tasks
---@param use_float boolean # Whether to use floating window
---@param group_by table # Grouping options
---@param display_opts ObsidianTaskDisplayOptions # Display options
---@return nil
function M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by, display_opts)
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)

	local handle
	---@type ObsidianTask[]
	local tasks = {}
	group_by = group_by or {}
	display_opts = display_opts or {}

	---@type fun() # Callback when process exits
	local function on_exit()
		if stdout then stdout:close() end
		if stderr then stderr:close() end
		handle:close()

		-- 应用文件过滤
		---@type ObsidianTask[]
		local file_filtered_tasks = {}

    -- require('plenary.log').info("[xxxhhh][exit handle all tasks]", tasks);
		-- 首先应用文件包含/排除过滤
		for _, task in ipairs(tasks) do
			local include_task = true

			-- 如果指定了 include_files，则只包含匹配的文件
			if filter.include_files and #filter.include_files > 0 then
				include_task = false
        -- require('plenary.log').info("[xxxhhh][changed to false][1]");
				for _, pattern in ipairs(filter.include_files) do
					if task.file_path:match(pattern) then
            -- require('plenary.log').info("[xxxhhh][changed to true][1]");
						include_task = true
						break
					end
				end
			end

			-- 如果指定了 exclude_files，则排除匹配的文件
			if include_task and filter.exclude_files and #filter.exclude_files > 0 then
				for _, pattern in ipairs(filter.exclude_files) do
					if task.file_path:match(pattern) then
						include_task = false
            -- require('plenary.log').info("[xxxhhh][changed to false][2]");
						break
					end
				end
			end

			-- 应用 status 过滤
			if include_task and filter.status then
				-- 如果 status 是字符串，转换为表格以便统一处理
				---@type string|string[]
				local status_filters = filter.status
				if type(status_filters) == "string" then
					status_filters = { status_filters }
				end
        assert(status_filters)

				-- 检查任务状态是否匹配任何指定的状态
				include_task = false
        -- require('plenary.log').info("[xxxhhh][changed to false][3]");
				for _, status in ipairs(status_filters) do
					if task.status == status then
						include_task = true
						break
					end
				end
			end

      -- require('plenary.log').info("[xxxhhh][last include flag]", include_task, task);
			if include_task then
				table.insert(file_filtered_tasks, task)
			end
		end

		-- 应用自定义过滤器
		---@type ObsidianTask[]
		local filtered_tasks = parser.filter_tasks(file_filtered_tasks, filter.custom)

		-- If no output data, notify user
		if #filtered_tasks == 0 then
			vim.schedule(function()
				vim.notify("No tasks found in the vault.", vim.log.levels.INFO)
			end)
		else
			vim.schedule(function()
				-- Process tasks by group
				---@type table<string, ObsidianTask[]>
				---@type string[]
				local grouped_tasks, group_order = parser.group_tasks(filtered_tasks, group_by)
        -- require('plenary.log').info("[xxxhhh][grouped task]", group_order, grouped_tasks);

				if use_float then
					display.display_tasks_float(filtered_tasks, grouped_tasks, group_order, display_opts)
				else
					display.display_tasks(filtered_tasks, grouped_tasks, group_order, display_opts)
				end
			end)
		end
	end

	handle = vim.loop.spawn("rg", {
		args = { "--line-number", "\\- \\[.\\].*#t", vault_path },
		stdio = { nil, stdout, stderr },
	}, vim.schedule_wrap(on_exit))

	---@param err? string # Error message if any
	---@param data? string # Data received from stdout
	vim.loop.read_start(stdout, function(err, data)
		assert(not err, err)
    -- require('plenary.log').info("xxxhhh rg data", data);
		if data then
			-- Split data by lines and store in tasks
			for line in data:gmatch("[^\r\n]+") do
				-- Extract task, file path and line number
				---@type string?, string?, string?
				local file_path, line_number, task_text = line:match("^(%S+):(%d+):(.+)$")
        -- require('plenary.log').info("[xxxhhh][rg line]", line, file_path, line_number, task_text);
				if task_text and file_path and line_number then
					---@type string?
					local status = task_text:match("%[(.?)%]")
					-- 保留完整的状态标记，包括方括号
					status = status and "[" .. status .. "]" or "[ ]"

					-- Extract due date
					---@type string?
					local due_date = task_text:match("📅 (%d%d%d%d%-%d%d%-%d%d)")

					-- Clean task text
					local clean_text = task_text:gsub("^%s*- %[.?%]", "")

					-- Extract priority
					---@type string
					local priority = parser.extract_priority(clean_text)

					-- Create task object
					---@type ObsidianTask
					local task = {
						text = clean_text,
						file_path = file_path,
						line_number = tonumber(line_number),
						status = status,
						due_date = due_date,
						priority = priority,
					}

					table.insert(tasks, task)
				end
			end
		end
	end)

	---@param err? string # Error message if any
	---@param data? string # Data received from stderr
	vim.loop.read_start(stderr, function(err, data)
		assert(not err, err)
		if data then
			vim.schedule(function()
				vim.notify(vim.inspect(data), vim.log.levels.ERROR)
			end)
		end
	end)
end

return M
