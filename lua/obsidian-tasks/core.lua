local M = {}

-- Store shared state
M.buffer_tasks = {}
M.task_index_map = {}

-- Importing other modules
local parser = require("obsidian-tasks.parser")

-- Save all task changes
function M.save_tasks_changes(buf, tasks)
  local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local updated_count = 0

  for _, line in ipairs(current_lines) do
    -- require('plenary.log').info('[xxxhhh][try saving line]', line);
    if line:match("^%d+%. %[.?%]") then  -- Ensure this is a task line, not a group title or help line
      -- require('plenary.log').info('[xxxhhh][valid task line]', line);
      local parsed = parser.parse_display_line(line)
      -- require('plenary.log').info('[xxxhhh][parsed line]', parsed);
      if parsed and parsed.index and tasks[parsed.index] then
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
function M.apply_task_changes(original_task, updated_task)
  -- Read file content
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
function M.save_current_tasks()
  local buf = vim.api.nvim_get_current_buf()

  -- Get tasks associated with this buffer
  local tasks = M.buffer_tasks[buf]

  if tasks then
    if M.save_tasks_changes(buf, tasks) then
      vim.api.nvim_set_option_value('modified', false, { buf = buf })
      vim.notify("Tasks saved successfully", vim.log.levels.INFO)
    else
      vim.notify("Failed to save some tasks", vim.log.levels.WARN)
    end
  else
    vim.notify("No tasks associated with this buffer", vim.log.levels.ERROR)
  end
end

-- Toggle task status at cursor
function M.toggle_task_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(buf, row-1, row, false)[1]

  -- Skip group title lines
  if line:match("^## ") then
    return
  end

  local parsed = parser.parse_display_line(line)
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

    local new_line = string.format("%d. %s %s%s <!-- %s:%d -->", 
      parsed.index, 
      parsed.status, 
      priority_text,
      parsed.text, 
      parsed.file_path, 
      parsed.line_number
    )

    vim.api.nvim_buf_set_lines(buf, row-1, row, false, {new_line})
    vim.api.nvim_set_option_value('modified', true, { buf = buf })
  end
end

return M
