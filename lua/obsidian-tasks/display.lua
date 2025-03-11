local M = {}

-- Help information
M.TASK_VIEW_HELP_LINES = {
  "-- Tasks List (q:close, s:save changes) --",
  "-- Change `[ ]` to `[x]` to mark tasks as done --",
  ""
}

local core = require("obsidian-tasks.core")
local parser = require("obsidian-tasks.parser")

-- Format task for display
function M.format_task_for_display(task, index)
  -- Format priority label (if not normal)
  local priority_text = ""
  if task.priority ~= "normal" then
    priority_text = "[" .. task.priority:upper() .. "] "
  end

  local display_text = string.format("%d. %s %s%s", 
    index, 
    task.status, 
    priority_text,
    task.text:gsub("^%[.?%] ", "")  -- Remove task status part
  )

  -- Add file path info (commented form, for internal tracking)
  local metadata = string.format(" <!-- %s:%d -->", task.file_path, task.line_number)
  return display_text .. metadata
end

-- Format grouped tasks for display
function M.format_grouped_tasks(grouped_tasks)
  local display_lines = {}
  local index_map = {}  -- Map display indices to original tasks
  local current_index = 1

  -- Sort group names for consistent display order
  local group_names = {}
  for name in pairs(grouped_tasks) do
    table.insert(group_names, name)
  end
  table.sort(group_names)

  -- Process each group
  for _, group_name in ipairs(group_names) do
    local tasks = grouped_tasks[group_name]

    -- Add group title (if not default group)
    if group_name ~= "default" then
      table.insert(display_lines, "")
      table.insert(display_lines, "## " .. group_name)
    end

    -- Process tasks in group
    for _, task in ipairs(tasks) do
      local formatted_line = M.format_task_for_display(task, current_index)
      table.insert(display_lines, formatted_line)
      index_map[current_index] = task
      current_index = current_index + 1
    end
  end

  return display_lines, index_map
end

-- Set up editable buffer
function M.setup_editable_buffer(buf, tasks)
  -- Set buffer options
  vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
  vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf }) -- Make editable
  vim.api.nvim_set_option_value('filetype', 'obstasks', { buf = buf }) -- Set custom filetype

  -- Apply changes on save
  vim.api.nvim_create_autocmd({"BufWriteCmd"}, {
    buffer = buf,
    callback = function()
      if core.save_tasks_changes(buf, tasks) then
        vim.api.nvim_set_option_value('modified', false, { buf = buf })
      end
    end
  })

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, M.TASK_VIEW_HELP_LINES)

  -- Keyboard mappings
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })

  local obsidian_tasks = require("obsidian-tasks")
  vim.keymap.set({ 'n' }, 's', obsidian_tasks.save_current_tasks, { buffer = buf, noremap = true, silent = true })

  -- Toggle task status
  vim.keymap.set({'n'}, '<space>', obsidian_tasks.toggle_task_at_cursor, { noremap = true, silent = true, buffer = buf })
end

-- Display editable task list
function M.display_tasks(tasks, grouped_tasks)
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(true, false) -- Create normal buffer

  -- Store task list association with buffer
  core.buffer_tasks[buf] = tasks

  -- Format task display
  local display_lines
  if grouped_tasks then
    display_lines, core.task_index_map = M.format_grouped_tasks(grouped_tasks)
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

  -- Open a new window and set to current buffer
  vim.api.nvim_set_current_buf(buf)

  -- Clean up task list association when buffer is deleted
  vim.api.nvim_create_autocmd({"BufDelete"}, {
    buffer = buf,
    callback = function()
      core.buffer_tasks[buf] = nil
      core.task_index_map = nil
    end,
    once = true
  })
end

-- Display editable task list in floating window
function M.display_tasks_float(tasks, grouped_tasks)
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, false)

  -- Store task list association with buffer
  core.buffer_tasks[buf] = tasks

  -- Format task display
  local display_lines
  if grouped_tasks then
    display_lines, core.task_index_map = M.format_grouped_tasks(grouped_tasks)
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

  -- Calculate window size and position
  local width = math.max(80, math.floor(vim.o.columns * 0.8))
  local height = math.min(#display_lines + 5, vim.o.lines - 4) -- Extra space for help text
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Window options
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded'
  }

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Set window options
  vim.api.nvim_set_option_value('winhl', 'NormalFloat:Normal', { win = win })

  -- Create autocmd to remind saving when leaving buffer
  vim.api.nvim_create_autocmd({"BufLeave"}, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_get_option_value('modified', { buf = buf }) then
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
    once = true
  })

  -- Clean up task list association when buffer is deleted
  vim.api.nvim_create_autocmd({"BufDelete"}, {
    buffer = buf,
    callback = function()
      core.buffer_tasks[buf] = nil
      core.task_index_map = nil
    end,
    once = true
  })
end

return M

