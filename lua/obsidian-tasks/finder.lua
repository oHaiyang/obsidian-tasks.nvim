local M = {}

local parser = require("obsidian-tasks.parser")
local display = require("obsidian-tasks.display")
local core = require("obsidian-tasks.core")

-- Main function to find tasks
function M.find_tasks(opts)
  opts = opts or {}
  local filter = opts.filter or function ()
    return true
  end
  local group_by = opts.group_by or {}
  local use_float = opts.float or false
  local vault_path = opts.vault_path

  -- Call ripgrep to find tasks
  M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by)
end

-- Find tasks using vim.loop and ripgrep
function M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local handle
  local tasks = {}
  group_by = group_by or {}

  local function on_exit()
    stdout:close()
    stderr:close()
    handle:close()

    -- Filter tasks
    local filtered_tasks = parser.filter_tasks(tasks, filter)

    -- If no output data, notify user
    if #filtered_tasks == 0 then
      vim.schedule(function()
        vim.notify("No tasks found in the vault.", vim.log.levels.INFO)
      end)
    else
      vim.schedule(function()
        -- Process tasks by group
        local grouped_tasks = parser.group_tasks(filtered_tasks, group_by)

        if use_float then
          display.display_tasks_float(filtered_tasks, grouped_tasks)
        else
          display.display_tasks(filtered_tasks, grouped_tasks)
        end
      end)
    end
  end

  handle = vim.loop.spawn('rg', {
    args = { '--line-number', '\\- \\[.\\].*#t', vault_path },
    stdio = { nil, stdout, stderr }
  }, vim.schedule_wrap(on_exit))

  vim.loop.read_start(stdout, function(err, data)
    assert(not err, err)
    if data then
      -- Split data by lines and store in tasks
      for line in data:gmatch("[^\r\n]+") do
        -- Extract task, file path and line number
        local file_path, line_number, task_text = line:match("^(%S+):(%d+):(.+)$")
        if task_text and file_path and line_number then
          local status = task_text:match("%[(.?)%]")
          status = status == " " and "[ ]" or "[x]"

          -- Extract due date
          local due_date = task_text:match("📅 (%d%d%d%d%-%d%d%-%d%d)")

          -- Clean task text
          local clean_text = task_text:gsub("^%s*- %[.?%]", "")

          -- Extract priority
          local priority = parser.extract_priority(clean_text)

          -- Create task object
          local task = {
            text = clean_text,
            file_path = file_path,
            line_number = tonumber(line_number),
            status = status,
            due_date = due_date,
            priority = priority
          }

          table.insert(tasks, task)
        end
      end
    end
  end)

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
