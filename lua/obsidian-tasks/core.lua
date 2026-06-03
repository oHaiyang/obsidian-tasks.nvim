---@class ObsidianTask
---@field text string # The task text content
---@field file_path string # Path to the file containing the task
---@field line_number? number # Line number where the task appears
---@field status string # Task status (e.g. "[ ]", "[x]")
---@field status_symbol? string # Status character inside the checkbox
---@field indentation? string # Original indentation before the list marker
---@field list_marker? string # Original list marker ("-", "*", "+", "1.", "1)")
---@field body? string # Original task body after the checkbox
---@field due_date? string # Due date in YYYY-MM-DD format if present
---@field priority? string # Task priority if present
---@field tags? string[] # Tags in the task description
---@field heading? string # Previous markdown heading in the source file
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
---@field global_filter? string # Optional global filter string
---@field globalFilter? string # Optional global filter string, camelCase compatibility
---@field global_query? string # Optional global query prepended to each tasks query
---@field globalQuery? string # Optional global query, camelCase compatibility

---@class ObsidianTasksFinder
---@field find_tasks fun(opts?: ObsidianTaskFinderOptions): nil # Find tasks matching criteria
---@field find_tasks_with_ripgrep fun(vault_path: string, filter: ObsidianTaskFilter, use_float: boolean, group_by: table, display_opts: ObsidianTaskDisplayOptions): nil # Find tasks using ripgrep

---@class ObsidianTasksConfig
---@field vault_path string # Path to the Obsidian vault
---@field global_filter? string # Optional global filter string
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
local cache = require("obsidian-tasks.cache")
local mutation = require("obsidian-tasks.mutation")
local status_model = require("obsidian-tasks.status")
local task_model = require("obsidian-tasks.task")

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function format_display_line(parsed)
	local priority_text = ""
	if parsed.priority and parsed.priority ~= "normal" then
		priority_text = "[" .. parsed.priority:upper() .. "] "
	end

	return string.format(
		"%s%d. %s %s%s [[%s#L%d]]",
		parsed.display_indentation or "",
		parsed.index,
		parsed.status,
		priority_text,
		parsed.text,
		parsed.file_path,
		parsed.line_number
	)
end

-- Save all task changes
---@param buf number # Buffer handle
---@param tasks ObsidianTask[] # Tasks to save
---@return boolean success # Whether the save was successful
function M.save_tasks_changes(buf, tasks)
	local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local updated_count = 0
	local failed_count = 0
	local index_map = M.task_index_map[buf] or {}

	for _, line in ipairs(current_lines) do
		-- require('plenary.log').info('[xxxhhh][try saving line]', line);
		if line:match("^%s*%d+%. %[.?%]") then -- Ensure this is a task line, not a group title or help line
			-- require('plenary.log').info('[xxxhhh][valid task line]', line);
			---@type ObsidianTask|nil
			local parsed = parser.parse_display_line(line)
			-- require('plenary.log').info('[xxxhhh][parsed line]', parsed);
			local original_task = parsed and parsed.index and (index_map[parsed.index] or tasks[parsed.index])
			if parsed and parsed.index and original_task then
				-- require('plenary.log').info('[xxxhhh][compare task]', original_task.status ~= parsed.status);
				-- Check if there are changes
				if original_task.status ~= parsed.status then
					-- Apply changes
					if M.apply_task_changes(original_task, parsed) then
						updated_count = updated_count + 1
					else
						failed_count = failed_count + 1
					end
				end
			end
		end
	end

	vim.notify(string.format("Updated %d task(s)", updated_count), vim.log.levels.INFO)
	return failed_count == 0
end

-- Apply task changes back to original file
---@param original_task ObsidianTask # Original task from file
---@param updated_task ObsidianTask # Updated task from display
---@return boolean success # Whether the changes were applied successfully
function M.apply_task_changes(original_task, updated_task)
	-- Read file content
	---@type string[]
	local lines = {}
	local file_path = original_task.file_path or updated_task.file_path
	local line_number = original_task.line_number or updated_task.line_number
	local file = io.open(file_path, "r")
	if not file then
		vim.notify("Cannot open file: " .. file_path, vim.log.levels.ERROR)
		return false
	end

	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()

	local ok, new_lines_or_err = mutation.apply_status_change_to_lines(lines, line_number, updated_task.status_symbol or updated_task.status, {
		file_path = file_path,
		source_task = original_task,
	})
	if not ok then
		vim.notify(new_lines_or_err .. ": " .. file_path, vim.log.levels.ERROR)
		return false
	end

	-- Write back to file
	file = io.open(file_path, "w")
	if not file then
		vim.notify("Cannot write to file: " .. file_path, vim.log.levels.ERROR)
		return false
	end

	for _, line in ipairs(new_lines_or_err) do
		file:write(line .. "\n")
	end
	file:close()
	cache.on_file_changed(file_path)

	return true
end

local function update_display_status_line(buf, row, parsed, next_symbol)
	parsed.status_symbol = status_model.normalize_symbol(next_symbol)
	parsed.status = status_model.status_text(parsed.status_symbol)
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	local updated = line:gsub("^(%s*%d+%. )%[.?%]", "%1" .. parsed.status, 1)
	if updated == line then
		updated = format_display_line(parsed)
	end
	vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { updated })
	vim.api.nvim_set_option_value("modified", true, { buf = buf })
	return true
end

local function apply_status_change_to_source_buffer(buf, row, next_symbol)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local ok, new_lines_or_err = mutation.apply_status_change_to_lines(lines, row, next_symbol, {
		file_path = vim.api.nvim_buf_get_name(buf),
	})
	if not ok then
		vim.notify(new_lines_or_err, vim.log.levels.ERROR)
		return false
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines_or_err)
	vim.api.nvim_set_option_value("modified", true, { buf = buf })
	return true
end

local function read_file_lines(file_path)
	local file = io.open(file_path, "r")
	if not file then
		return nil, "Cannot open file: " .. file_path
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()
	return lines
end

local function write_file_lines(file_path, lines)
	local file = io.open(file_path, "w")
	if not file then
		return false, "Cannot write to file: " .. file_path
	end
	for _, line in ipairs(lines) do
		file:write(line .. "\n")
	end
	file:close()
	return true
end

function M.apply_postpone_changes(original_task, expr)
	local file_path = original_task.file_path
	local line_number = original_task.line_number
	local lines, read_err = read_file_lines(file_path)
	if not lines then
		vim.notify(read_err, vim.log.levels.ERROR)
		return false
	end

	local ok, new_lines_or_err, _, field, target = mutation.apply_postpone_to_lines(lines, line_number, expr, {
		file_path = file_path,
		source_task = original_task,
	})
	if not ok then
		vim.notify(new_lines_or_err .. ": " .. file_path, vim.log.levels.ERROR)
		return false
	end

	local written, write_err = write_file_lines(file_path, new_lines_or_err)
	if not written then
		vim.notify(write_err, vim.log.levels.ERROR)
		return false
	end
	cache.on_file_changed(file_path)

	vim.notify(string.format("Postponed %s date to %s", field, target), vim.log.levels.INFO)
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
	if parsed then
		local next_symbol = status_model.next_symbol(parsed.status_symbol, get_config())
		return update_display_status_line(buf, row, parsed, next_symbol)
	end

	local source_task = task_model.parse_line({
		line = line,
		file_path = vim.api.nvim_buf_get_name(buf),
		line_number = row,
	})
	if source_task then
		local next_symbol = status_model.next_symbol(source_task.status_symbol, get_config())
		return apply_status_change_to_source_buffer(buf, row, next_symbol)
	end

	return false
end

function M.change_task_status_at_cursor(status)
	local next_symbol = status_model.resolve_symbol(status, get_config())
	if not next_symbol then
		vim.notify("Unknown task status: " .. tostring(status), vim.log.levels.ERROR)
		return false
	end

	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]

	local parsed = parser.parse_display_line(line)
	if parsed then
		return update_display_status_line(buf, row, parsed, next_symbol)
	end

	local source_task = task_model.parse_line({
		line = line,
		file_path = vim.api.nvim_buf_get_name(buf),
		line_number = row,
	})
	if source_task then
		return apply_status_change_to_source_buffer(buf, row, next_symbol)
	end

	return false
end

function M.postpone_task_at_cursor(expr)
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]

	local parsed = parser.parse_display_line(line)
	if parsed then
		local index_map = M.task_index_map[buf] or {}
		local original_task = parsed.index and index_map[parsed.index]
		if not original_task then
			vim.notify("No source task for display line", vim.log.levels.ERROR)
			return false
		end
		if M.apply_postpone_changes(original_task, expr) then
			require("obsidian-tasks.display").refresh_tasks_view()
			return true
		end
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local ok, new_lines_or_err, _, field, target = mutation.apply_postpone_to_lines(lines, row, expr, {
		file_path = vim.api.nvim_buf_get_name(buf),
	})
	if not ok then
		vim.notify(new_lines_or_err, vim.log.levels.ERROR)
		return false
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines_or_err)
	vim.api.nvim_set_option_value("modified", true, { buf = buf })
	vim.notify(string.format("Postponed %s date to %s", field, target), vim.log.levels.INFO)
	return true
end

return M
