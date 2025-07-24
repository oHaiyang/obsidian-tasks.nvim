---@class ObsidianTask
---@field text string # The task text content
---@field file_path string # Path to the file containing the task
---@field line_number? number # Line number where the task appears
---@field status string # Task status (e.g. "[ ]", "[x]")
---@field due_date? string # Due date in YYYY-MM-DD format if present
---@field priority? string # Task priority if present
---@field index? number # Task index in the display

---@class ObsidianTaskFilter
---@field custom? fun(task: ObsidianTask): boolean # Custom filter function
---@field include_files? string[] # Patterns of files to include
---@field exclude_files? string[] # Patterns of files to exclude
---@field status? string|string[] # Status filter(s)

---@class ObsidianTaskDisplayOptions
---@field hierarchical_headings? boolean # Whether to display headings hierarchically

---@class ObsidianTaskFinderOptions
---@field filter? ObsidianTaskFilter|fun(task: ObsidianTask): boolean # Filter criteria
---@field group_by? table # Grouping options
---@field float? boolean # Whether to use floating window
---@field vault_path string # Path to the Obsidian vault
---@field hierarchical_headings? boolean # Whether to display headings hierarchically

---@class ObsidianTasksFinder
---@field find_tasks fun(opts?: ObsidianTaskFinderOptions): nil # Find tasks matching criteria
---@field find_tasks_with_ripgrep fun(vault_path: string, filter: ObsidianTaskFilter, use_float: boolean, group_by: table, display_opts: ObsidianTaskDisplayOptions): nil # Find tasks using ripgrep

---@class ObsidianTasksConfig
---@field vault_path string # Path to the Obsidian vault
---@field display? ObsidianTasksDisplayConfig # Display configuration options

---@class ObsidianTasksDisplayConfig
---@field hierarchical_headings? boolean # Whether to display headings hierarchically

---@class ObsidianTasks
---@field config ObsidianTasksConfig # Configuration options
---@field setup fun(config?: ObsidianTasksConfig): ObsidianTasks # Initialize the plugin
---@field save_current_tasks fun(): boolean # Save the current tasks
---@field toggle_task_at_cursor fun(): boolean # Toggle the task at the cursor position

---@class ObsidianTasksCore
---@field buffer_tasks table<number, ObsidianTask[]> # Tasks associated with each buffer
---@field task_index_map table<number, table<number, ObsidianTask>> # Mapping of task indices to tasks
---@field save_tasks_changes fun(buf: number, tasks: ObsidianTask[]): boolean # Save task changes to files
---@field apply_task_changes fun(original_task: ObsidianTask, updated_task: ObsidianTask): boolean # Apply task changes to original file
---@field save_current_tasks fun(): boolean # Save tasks in current buffer
---@field toggle_task_at_cursor fun(): boolean # Toggle task status at cursor position
local M = {}

-- Store shared state
---@type table<number, ObsidianTask[]>
M.buffer_tasks = {}
---@type table<number, table<number, ObsidianTask>>
M.task_index_map = {}

-- Importing other modules
local parser = require("obsidian-tasks.parser")

-- Save all task changes
---@param buf number # Buffer handle
---@param tasks ObsidianTask[] # Tasks to save
---@return boolean success # Whether the save was successful
function M.save_tasks_changes(buf, tasks)
	local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local updated_count = 0

	for _, line in ipairs(current_lines) do
		-- require('plenary.log').info('[xxxhhh][try saving line]', line);
		if line:match("^%d+%. %[.?%]") then -- Ensure this is a task line, not a group title or help line
			-- require('plenary.log').info('[xxxhhh][valid task line]', line);
			---@type ObsidianTask|nil
			local parsed = parser.parse_display_line(line)
			-- require('plenary.log').info('[xxxhhh][parsed line]', parsed);
			if parsed and parsed.index and tasks[parsed.index] then
				---@type ObsidianTask
				local original_task = tasks[parsed.index]

				-- require('plenary.log').info('[xxxhhh][compare task]', original_task.status ~= parsed.status);
				-- Check if there are changes
				if original_task.status ~= parsed.status then
					-- Apply changes
					if M.apply_task_changes(original_task, parsed) then
						updated_count = updated_count + 1
					end
				end
			end
		end
	end

	vim.notify(string.format("Updated %d task(s)", updated_count), vim.log.levels.INFO)
	return updated_count > 0
end

-- Apply task changes back to original file
---@param original_task ObsidianTask # Original task from file
---@param updated_task ObsidianTask # Updated task from display
---@return boolean success # Whether the changes were applied successfully
function M.apply_task_changes(original_task, updated_task)
	-- Read file content
	---@type string[]
	local lines = {}
	local file = io.open(updated_task.file_path, "r")
	if not file then
		vim.notify("Cannot open file: " .. updated_task.file_path, vim.log.levels.ERROR)
		return false
	end

	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()

	-- Find original line
	local original_line = lines[updated_task.line_number]
	if not original_line then
		vim.notify("Line not found in file", vim.log.levels.ERROR)
		return false
	end

	-- Create new task text
	local new_status = updated_task.status

	-- Replace status, preserve other formatting
	local new_line = original_line:gsub("%[.?%]", new_status)

	-- Write back to file
	file = io.open(updated_task.file_path, "w")
	if not file then
		vim.notify("Cannot write to file: " .. updated_task.file_path, vim.log.levels.ERROR)
		return false
	end

	for i, line in ipairs(lines) do
		if i == updated_task.line_number then
			file:write(new_line .. "\n")
		else
			file:write(line .. "\n")
		end
	end
	file:close()

	return true
end

-- Add this new function to save current buffer's tasks
---@return boolean success # Whether the save was successful
function M.save_current_tasks()
	local buf = vim.api.nvim_get_current_buf()

	-- Get tasks associated with this buffer
	---@type ObsidianTask[]|nil
	local tasks = M.buffer_tasks[buf]

	if tasks then
		if M.save_tasks_changes(buf, tasks) then
			vim.api.nvim_set_option_value("modified", false, { buf = buf })
			vim.notify("Tasks saved successfully", vim.log.levels.INFO)
			return true
		else
			vim.notify("Failed to save some tasks", vim.log.levels.WARN)
			return false
		end
	else
		vim.notify("No tasks associated with this buffer", vim.log.levels.ERROR)
		return false
	end
end

-- Toggle task status at cursor
---@return boolean success # Whether the toggle was successful
function M.toggle_task_at_cursor()
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]

	-- Skip group title lines
	if line:match("^## ") then
		return false
	end

	---@type ObsidianTask|nil
	local parsed = parser.parse_display_line(line)
	vim.notify(vim.inspect(parsed))
	if parsed then
		-- Toggle status
		if parsed.status == "[ ]" then
			parsed.status = "[x]"
		else
			parsed.status = "[ ]"
		end

		-- Update line
		local priority_text = ""
		if parsed.priority ~= "normal" then
			priority_text = "[" .. parsed.priority:upper() .. "] "
		end

		local new_line = string.format(
			"%d. %s %s%s [[%s#L%d]]",
			parsed.index,
			parsed.status,
			priority_text,
			parsed.text,
			parsed.file_path,
			parsed.line_number
		)

		vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { new_line })
		vim.api.nvim_set_option_value("modified", true, { buf = buf })
		return true
	end

	return false
end

return M
