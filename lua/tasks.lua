-- 帮助信息
local TASK_VIEW_HELP_LINES = {
  "-- Tasks List (q:close, s:save changes) --",
  "-- Change `[ ]` to `[x]` to mark tasks as done --",
  ""
}

local M = {}

-- 任务对象结构
-- task = {
--   text = "任务文本",
--   file_path = "文件路径",
--   line_number = 行号,
--   status = "[ ]" 或 "[x]",
--   due_date = "2025-01-01" 或 nil
-- }

M.buffer_tasks = {}

-- 使用 vim.loop 和 ripgrep 查找任务
function M.find_tasks_with_ripgrep(vault_path, query, use_float)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local handle
  local tasks = {}

  -- 解析查询语句
  local function parse_query(query)
    local filters = {}
    if query:match("not done") then
      filters.not_done = true
    elseif query:match("done") then
      filters.done = true
    end
    local due_date = query:match("due (%d%d%d%d%-%d%d%-%d%d)")
    if due_date then
      filters.due_date = due_date
    end
    return filters
  end

  -- 过滤任务
  local function filter_tasks(tasks, filters)
    local filtered_tasks = {}
    for _, task in ipairs(tasks) do
      local include = true
      if filters.not_done then
        include = task.status == "[ ]"
      elseif filters.done then
        include = task.status ~= "[ ]"
      end
      if include and filters.due_date then
        include = task.due_date == filters.due_date
      end
      if include then
        table.insert(filtered_tasks, task)
      end
    end
    return filtered_tasks
  end

  local function on_exit()
    stdout:close()
    stderr:close()
    handle:close()

    -- 解析查询语句
    local filters = parse_query(query)
    -- 过滤任务
    local filtered_tasks = filter_tasks(tasks, filters)

    -- 如果没有输出数据，通知用户
    if #filtered_tasks == 0 then
      vim.schedule(function()
        vim.notify("No tasks found in the vault.", vim.log.levels.INFO)
      end)
    else
      vim.schedule(function()
        if use_float then
          M.display_tasks_float(filtered_tasks)
        else
          M.display_tasks(filtered_tasks)
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
      -- 按行分割数据并存储到 tasks
      for line in data:gmatch("[^\r\n]+") do
        -- 提取任务和文件路径和行号
        local file_path, line_number, task_text = line:match("^(%S+):(%d+):(.+)$")
        if task_text and file_path and line_number then
          local status = task_text:match("%[(.?)%]")
          status = status == " " and "[ ]" or "[x]"
          
          -- 提取截止日期
          local due_date = task_text:match("📅 (%d%d%d%d%-%d%d%-%d%d)")
          
          -- 创建任务对象
          local task = {
            text = task_text:gsub("^%s*- %[(.?)%]", ""),  -- 移除前导的 "- [.]"
            file_path = file_path,
            line_number = tonumber(line_number),
            status = status,
            due_date = due_date
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

-- 将任务格式化为显示行
local function format_task_for_display(task, index)
  local display_text = string.format("%d. %s %s", 
    index, 
    task.status, 
    task.text:gsub("^%[.?%] ", "")  -- 移除任务状态部分
  )
  
  -- 添加文件路径信息（注释掉的形式，用于内部跟踪）
  local metadata = string.format(" <!-- %s:%d -->", task.file_path, task.line_number)
  return display_text .. metadata
end

-- 从显示行解析任务信息
local function parse_display_line(line)
  local index, status, rest = line:match("^(%d+)%. (%[.?%]) (.+)")
  local text, file_path, line_number = rest:match("(.+) <!%-%- (.+):(%d+) %-%->$")
  
  if not (index and status and text and file_path and line_number) then
    return nil
  end
  
  return {
    index = tonumber(index),
    status = status,
    text = text,
    file_path = file_path,
    line_number = tonumber(line_number)
  }
end

-- 将任务应用回原文件
local function apply_task_changes(original_task, updated_task)
  -- 读取文件内容
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
  
  -- 找到原始行
  local original_line = lines[updated_task.line_number]
  if not original_line then
    vim.notify("Line not found in file", vim.log.levels.ERROR)
    return false
  end
  
  -- 构造新的任务文本
  local new_status = updated_task.status
  local new_text = updated_task.text
  
  -- 替换状态和文本，保留其他格式
  local new_line = original_line:gsub("%[.?%]", new_status)
  
  -- 写回文件
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

-- 保存所有任务修改
local function save_tasks_changes(buf, tasks)
  local current_lines = vim.api.nvim_buf_get_lines(buf, #TASK_VIEW_HELP_LINES, -1, false)
  local updated_count = 0
  
  for _, line in ipairs(current_lines) do
    local parsed = parse_display_line(line)
    if parsed then
      local original_task = tasks[parsed.index]
      if original_task then
        -- 检查是否有修改
        if original_task.status ~= parsed.status or 
          original_task.text ~= parsed.text then
          if original_task.status ~= parsed.status then
            require('plenary.log').info("xxxhhh status changed", original_task.status, parsed.status);
          end
          if original_task.text ~= parsed.text then
            require('plenary.log').info("xxxhhh text changed ||" .. vim.inspect(original_task) .. "||" .. vim.inspect(parsed) .. "||");
          end

          -- 应用修改
          if apply_task_changes(original_task, parsed) then
            updated_count = updated_count + 1
          end
        end
      end
    end
  end
  
  vim.notify(string.format("Updated %d task(s)", updated_count), vim.log.levels.INFO)
  return updated_count > 0
end

-- 设置可编辑的 buffer
local function setup_editable_buffer(buf, tasks)
  -- 设置 buffer 的选项
  vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
  vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf }) -- 设置为可编辑
  vim.api.nvim_set_option_value('filetype', 'obstasks', { buf = buf }) -- 设置自定义的 filetype

  -- 在保存时应用修改
  vim.api.nvim_create_autocmd({"BufWriteCmd"}, {
    buffer = buf,
    callback = function()
      if save_tasks_changes(buf, tasks) then
        vim.api.nvim_set_option_value('modified', false, { buf = buf })
      end
    end
  })

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, TASK_VIEW_HELP_LINES)

  -- 键盘映射
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })
  
  vim.keymap.set({ 'n', 's' }, 's', M.save_current_tasks, { buffer = buf, noremap = true, silent = true })
  
  -- 切换任务状态
  vim.keymap.set({'n'}, '<spance>', M.toggle_task_at_cursor, { noremap = true, silent = true, buffer = buf })
end

-- 添加这个新函数来保存当前缓冲区的任务
function M.save_current_tasks()
  local buf = vim.api.nvim_get_current_buf()
  
  -- 获取与此缓冲区关联的任务列表
  -- 我们需要一种方式来存储每个缓冲区的任务列表
  local tasks = M.buffer_tasks[buf]
  
  if tasks then
    if save_tasks_changes(buf, tasks) then
      vim.api.nvim_set_option_value('modified', false, { buf = buf })
      vim.notify("Tasks saved successfully", vim.log.levels.INFO)
    else
      vim.notify("Failed to save some tasks", vim.log.levels.WARN)
    end
  else
    vim.notify("No tasks associated with this buffer", vim.log.levels.ERROR)
  end
end

-- 显示可编辑的任务列表
function M.display_tasks(tasks)
  -- 创建一个新的 buffer
  local buf = vim.api.nvim_create_buf(true, false) -- 创建正常的 buffer
  
  -- 存储任务列表与缓冲区的关联
  M.buffer_tasks[buf] = tasks
  
  -- 格式化任务显示
  local display_lines = {}
  for i, task in ipairs(tasks) do
    table.insert(display_lines, format_task_for_display(task, i))
  end
  
  -- 设置 buffer 的内容
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  
  -- 设置 buffer 为可编辑
  setup_editable_buffer(buf, tasks)
  
  -- 打开一个新的窗口并设置为当前 buffer
  vim.api.nvim_set_current_buf(buf)
  
  -- 当缓冲区被删除时清理关联的任务列表
  vim.api.nvim_create_autocmd({"BufDelete"}, {
    buffer = buf,
    callback = function()
      M.buffer_tasks[buf] = nil
    end,
    once = true
  })
end

-- 在浮动窗口中显示可编辑的任务列表
function M.display_tasks_float(tasks)
  -- 创建一个新的 buffer
  local buf = vim.api.nvim_create_buf(false, false)
  
  -- 存储任务列表与缓冲区的关联
  M.buffer_tasks[buf] = tasks
  
  -- 格式化任务显示
  local display_lines = {}
  for i, task in ipairs(tasks) do
    table.insert(display_lines, format_task_for_display(task, i))
  end
  
  -- 设置 buffer 的内容
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  
  -- 设置 buffer 为可编辑
  setup_editable_buffer(buf, tasks)
  
  -- 计算窗口大小和位置
  local width = math.max(80, math.floor(vim.o.columns * 0.8))
  local height = math.min(#display_lines + 5, vim.o.lines - 4) -- 额外空间给帮助文本
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)
  
  -- 窗口配置
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded'
  }
  
  -- 创建浮动窗口
  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- 设置窗口选项
  vim.api.nvim_set_option_value('winhl', 'NormalFloat:Normal', { win = win })
  
  -- 创建自动命令，当用户离开缓冲区时提醒保存
  vim.api.nvim_create_autocmd({"BufLeave"}, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_get_option_value('modified', { buf = buf }) then
        local choice = vim.fn.confirm("Save changes?", "&Yes\n&No\n&Cancel", 1)
        if choice == 1 then -- Yes
          M.save_current_tasks() -- 使用新函数
        elseif choice == 3 then -- Cancel
          return true -- 阻止离开
        end
      end
      
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
    once = true
  })
  
  -- 当缓冲区被删除时清理关联的任务列表
  vim.api.nvim_create_autocmd({"BufDelete"}, {
    buffer = buf,
    callback = function()
      M.buffer_tasks[buf] = nil
    end,
    once = true
  })
end

-- 切换当前行任务的状态
function M.toggle_task_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(buf, row-1, row, false)[1]
  
  local parsed = parse_display_line(line)
  if parsed then
    -- 切换状态
    if parsed.status == "[ ]" then
      parsed.status = "[x]"
    else
      parsed.status = "[ ]"
    end
    
    -- 更新行
    local new_line = string.format("%d. %s %s <!-- %s:%d -->", 
      parsed.index, 
      parsed.status, 
      parsed.text, 
      parsed.file_path, 
      parsed.line_number
    )
    
    vim.api.nvim_buf_set_lines(buf, row-1, row, false, {new_line})
    vim.api.nvim_set_option_value('modified', true, { buf = buf })
  end
end

-- 设置模块
function M.setup()
  -- 创建常规命令
  vim.api.nvim_create_user_command('FindTasksInVault', function(opts)
    local vault_path = "/Users/didi/Notes"  -- 替换为你的 vault 路径
    local query = opts.args
    M.find_tasks_with_ripgrep(vault_path, query, false)
  end, { nargs = '*' })
  
  -- 创建浮动窗口命令
  vim.api.nvim_create_user_command('FindTasksInVaultFloat', function(opts)
    local vault_path = "/Users/didi/Notes"  -- 替换为你的 vault 路径
    local query = opts.args
    M.find_tasks_with_ripgrep(vault_path, query, true)
  end, { nargs = '*' })
  
  vim.treesitter.language.register("markdown", "obstasks")
end

return M
