local M = {}

-- Help information
M.TASK_VIEW_HELP_LINES = {
	"-- Tasks List (q:close, <c-s>:save changes, <c-r>:refresh) --",
	"-- Change `[ ]` to `[x]` to mark tasks as done --",
	"",
}

local core = require("obsidian-tasks.core")
local parser = require("obsidian-tasks.parser")

-- Store the last used options for refresh functionality
M.last_finder_opts = {}

-- Format task for display
function M.format_task_for_display(task, index)
	-- Format priority label (if not normal)
	local priority_text = ""
	if task.priority ~= "normal" then
		priority_text = "[" .. task.priority:upper() .. "] "
	end

	local display_text = string.format(
		"%d. %s %s%s",
		index,
		task.status,
		priority_text,
		task.text:gsub("^%[.?%] ", "") -- Remove task status part
	)

	-- Add file path info as wiki link (for internal tracking and navigation)
	local metadata = string.format(" [[%s#L%d]]", task.file_path, task.line_number)
	return display_text .. metadata
end

-- Format grouped tasks for display
function M.format_grouped_tasks(grouped_tasks, opts)
	-- require('plenary.log').info('[xxxhhh][grouped_tasks]', grouped_tasks, opts)
	opts = opts or {}
	local use_hierarchical_headings = opts.hierarchical_headings or false

	local display_lines = {}
	local index_map = {} -- Map display indices to original tasks
	local current_index = 1

	-- Sort group names for consistent display order
	local group_names = {}
	for name in pairs(grouped_tasks) do
		table.insert(group_names, name)
	end
	table.sort(group_names)

	-- For hierarchical headings, we need to track which headings we've already displayed
	local displayed_headings = {}
	
	-- Process each group
	for _, group_name in ipairs(group_names) do
		local tasks = grouped_tasks[group_name]

		-- Add group title (if not default group)
		if group_name ~= "default" then
			table.insert(display_lines, "")

			if use_hierarchical_headings then
				-- For hierarchical headings, determine the heading level based on the number of colons
				local parts = {}
				for part in group_name:gmatch("[^:]+") do
					table.insert(parts, part)
				end

				-- Build up the heading path as we go
				local current_path = ""
				
				-- Add all parts as separate headings with appropriate levels, but only if not already displayed
				for i, part in ipairs(parts) do
					local level = i + 1 -- Start at level 2
					if level > 6 then level = 6 end -- Max heading level is 6
					
					-- Build the current path to this heading level
					if current_path == "" then
						current_path = part
					else
						current_path = current_path .. ":" .. part
					end
					
					-- Only display this heading if we haven't seen it before
					if not displayed_headings[current_path] then
						table.insert(display_lines, string.rep("#", level) .. " " .. part)
						displayed_headings[current_path] = true
					end
				end
			else
				-- Traditional flat heading style
				table.insert(display_lines, "## " .. group_name:gsub(":", " > "))
			end
		end

		-- Process tasks in group
		for _, task in ipairs(tasks) do
			local formatted_line = M.format_task_for_display(task, current_index)
			table.insert(display_lines, formatted_line)
			index_map[current_index] = task
			current_index = current_index + 1
		end
	end

	-- require('plenary.log').info('[xxxhhh][display lines]', display_lines)
	return display_lines, index_map
end

-- Refresh the current task list
function M.refresh_tasks_view()
	local buf = vim.api.nvim_get_current_buf()
	local tasks = core.buffer_tasks[buf]
	
	if not tasks or #tasks == 0 then
		vim.notify("No tasks to refresh", vim.log.levels.WARN)
		return
	end
	
	-- Store current window and cursor position
	local win = vim.api.nvim_get_current_win()
	local cursor_pos = vim.api.nvim_win_get_cursor(win)
	
	-- Get the first task's file path to determine vault path
	local first_task = tasks[1]
	local vault_path = first_task and first_task.file_path:match("^(.+)/[^/]+$") or nil
	
	if not vault_path then
		vim.notify("Could not determine vault path for refresh", vim.log.levels.ERROR)
		return
	end
	
	-- Check if we're in a floating window
	local win_config = vim.api.nvim_win_get_config(win)
	local is_float = win_config.relative and win_config.relative ~= ""
	
	-- Get current buffer options to preserve them
	local hierarchical_headings = false
	
	-- Try to determine current grouping from buffer content
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	for _, line in ipairs(lines) do
		if line:match("^## ") then
			-- Found a heading, check if it's hierarchical
			if line:match("> ") then
				-- Traditional flat heading with ">"
				hierarchical_headings = false
			else
				-- Likely hierarchical
				hierarchical_headings = true
			end
			break
		end
	end
	
	-- Close current buffer
	vim.cmd("bd!")
	
	-- Re-run the finder with the same options as before
	local finder = require("obsidian-tasks.finder")
	
	-- Create options table for the finder
	local opts = {
		vault_path = vault_path,
		float = is_float,
		hierarchical_headings = hierarchical_headings
	}
	
	-- Reuse the last filter and group_by settings if available
	if M.last_finder_opts.filter then
		opts.filter = M.last_finder_opts.filter
	end
	
	if M.last_finder_opts.group_by then
		opts.group_by = M.last_finder_opts.group_by
	end
	
	finder.find_tasks(opts)
	
	-- Notify user
	vim.notify("Tasks refreshed", vim.log.levels.INFO)
end

-- Set up editable buffer
function M.setup_editable_buffer(buf, tasks)
	-- Set buffer options
	vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf }) -- Make editable
	vim.api.nvim_set_option_value("filetype", "obstasks", { buf = buf }) -- Set custom filetype

	-- Apply changes on save
	vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
		buffer = buf,
		callback = function()
			if core.save_tasks_changes(buf, tasks) then
				vim.api.nvim_set_option_value("modified", false, { buf = buf })
			end
		end,
	})

	vim.api.nvim_buf_set_lines(buf, 0, 0, false, M.TASK_VIEW_HELP_LINES)

	-- Keyboard mappings
	vim.api.nvim_buf_set_keymap(buf, "n", "q", ":bd!<CR>", { noremap = true, silent = true })

	local obsidian_tasks = require("obsidian-tasks")
	vim.keymap.set({ "n" }, "<c-s>", obsidian_tasks.save_current_tasks, { buffer = buf, noremap = true, silent = true })
	
	-- Add refresh functionality
	vim.keymap.set({ "n" }, "<c-r>", M.refresh_tasks_view, { buffer = buf, noremap = true, silent = true })

	-- Toggle task status
	vim.keymap.set(
		{ "n" },
		"<space>",
		obsidian_tasks.toggle_task_at_cursor,
		{ noremap = true, silent = true, buffer = buf }
	)

	-- Add jump to task source file functionality for gd and gf
	local function jump_to_task_source()
		local line = vim.api.nvim_get_current_line()
		local file_path, line_number = line:match("%[%[([^#]+)#L(%d+)%]%]")

		if file_path and line_number then
			-- Close current buffer
			vim.cmd("bd")
			-- Open the source file at the specified line
			vim.cmd("edit +" .. line_number .. " " .. file_path)
		end
	end

	-- Map both gd and gf to the jump function
	vim.keymap.set({ "n" }, "gd", jump_to_task_source, { noremap = true, silent = true, buffer = buf })
	vim.keymap.set({ "n" }, "gf", jump_to_task_source, { noremap = true, silent = true, buffer = buf })
end

-- Display editable task list
function M.display_tasks(tasks, grouped_tasks, opts)
	opts = opts or {}

	-- Create a new buffer
	local buf = vim.api.nvim_create_buf(true, false) -- Create normal buffer

	-- Store task list association with buffer
	core.buffer_tasks[buf] = tasks

	-- Format task display
	local display_lines
	if grouped_tasks then
		display_lines, core.task_index_map = M.format_grouped_tasks(grouped_tasks, opts)
	else
		display_lines = {}
		for i, task in ipairs(tasks) do
			table.insert(display_lines, M.format_task_for_display(task, i))
			core.task_index_map = core.task_index_map or {}
			core.task_index_map[i] = task
		end
	end

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

	-- Make buffer editable
	M.setup_editable_buffer(buf, tasks)

	-- Reset the modified flag after setting content
	vim.api.nvim_set_option_value("modified", false, { buf = buf })

	-- Open a new window and set to current buffer
	vim.api.nvim_set_current_buf(buf)

	-- Clean up task list association when buffer is deleted
	vim.api.nvim_create_autocmd({ "BufDelete" }, {
		buffer = buf,
		callback = function()
			core.buffer_tasks[buf] = nil
			core.task_index_map = nil
		end,
		once = true,
	})
end

-- Display editable task list in floating window
function M.display_tasks_float(tasks, grouped_tasks, opts)
	opts = opts or {}

	-- Create a new buffer
	local buf = vim.api.nvim_create_buf(false, false)

	-- Store task list association with buffer
	core.buffer_tasks[buf] = tasks

	-- Format task display
	local display_lines
	if grouped_tasks then
		display_lines, core.task_index_map = M.format_grouped_tasks(grouped_tasks, opts)
	else
		display_lines = {}
		for i, task in ipairs(tasks) do
			table.insert(display_lines, M.format_task_for_display(task, i))
			core.task_index_map = core.task_index_map or {}
			core.task_index_map[i] = task
		end
	end

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

	-- Make buffer editable
	M.setup_editable_buffer(buf, tasks)

	-- Reset the modified flag after setting content
	vim.api.nvim_set_option_value("modified", false, { buf = buf })

	-- Calculate window size and position
	local width = math.max(80, math.floor(vim.o.columns * 0.8))
	local height = math.min(#display_lines + 10, vim.o.lines - 4) -- Extra space for help text
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Window options
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
	}

	-- Create floating window
	local win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Set window options
	vim.api.nvim_set_option_value("winhl", "NormalFloat:Normal", { win = win })

	-- Create autocmd to remind saving when leaving buffer
	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		buffer = buf,
		callback = function()
			if vim.api.nvim_get_option_value("modified", { buf = buf }) then
				local choice = vim.fn.confirm("Save changes?", "&Yes\n&No\n&Cancel", 1)
				if choice == 1 then -- Yes
					require("obsidian-tasks").save_current_tasks()
				elseif choice == 3 then -- Cancel
					return true -- Prevent leaving
				end
			end

			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
		once = true,
	})

	-- Clean up task list association when buffer is deleted
	vim.api.nvim_create_autocmd({ "BufDelete" }, {
		buffer = buf,
		callback = function()
			core.buffer_tasks[buf] = nil
			core.task_index_map = nil
		end,
		once = true,
	})
end

return M
