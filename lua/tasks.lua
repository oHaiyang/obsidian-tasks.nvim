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
--   due_date = "2025-01-01" 或 nil,
--   priority = "highest" | "high" | "medium" | "normal" | "low" | "lowest"
-- }

-- 存储优先级 emoji 对应的名称
local PRIORITY_EMOJIS = {
  ["🔺"] = "highest",
  ["⏫"] = "high",
  ["🔼"] = "medium",
  ["🔽"] = "low",
  ["⏬️"] = "lowest"
}

-- 优先级顺序（用于排序）
local PRIORITY_ORDER = {
  highest = 1,
  high = 2,
  medium = 3,
  normal = 4,
  low = 5,
  lowest = 6
}

M.buffer_tasks = {}

-- 提取任务优先级
local function extract_priority(task_text)
  for emoji, priority in pairs(PRIORITY_EMOJIS) do
    if task_text:find(emoji) then
      return priority
    end
  end
  return "normal"
end

-- 将任务格式化为显示行
local function format_task_for_display(task, index)
  -- 格式化优先级标签（如果不是 normal）
  local priority_text = ""
  if task.priority ~= "normal" then
    priority_text = "[" .. task.priority:upper() .. "] "
  end

  local display_text = string.format("%d. %s %s%s", 
    index, 
    task.status, 
    priority_text,
    task.text:gsub("^%[.?%] ", "")  -- 移除任务状态部分
  )

  -- 添加文件路径信息（注释掉的形式，用于内部跟踪）
  local metadata = string.format(" <!-- %s:%d -->", task.file_path, task.line_number)
  return display_text .. metadata
end

-- 为分组任务格式化显示内容
local function format_grouped_tasks(grouped_tasks)
  local display_lines = {}
  local index_map = {}  -- 保存显示索引到原始任务的映射
  local current_index = 1

  -- 对组名进行排序以保证一致的显示顺序
  local group_names = {}
  for name in pairs(grouped_tasks) do
    table.insert(group_names, name)
  end
  table.sort(group_names)

  -- 处理每个分组
  for _, group_name in ipairs(group_names) do
    local tasks = grouped_tasks[group_name]

    -- 添加组标题（如果不是默认组）
    if group_name ~= "default" then
      table.insert(display_lines, "")
      table.insert(display_lines, "## " .. group_name)
    end

    -- 处理组内任务
    for _, task in ipairs(tasks) do
      local formatted_line = format_task_for_display(task, current_index)
      table.insert(display_lines, formatted_line)
      index_map[current_index] = task
      current_index = current_index + 1
    end
  end

  return display_lines, index_map
end

-- 提供一个 find_tasks 作为插件的主 lua API
function M.find_tasks(opts)
  opts = opts or {}
  local filter = opts.filter or ""
  local group_by = opts.group_by or {}
  local use_float = opts.float or false
  local vault_path = opts.vault_path or "/Users/didi/Notes" -- 默认路径

  -- 调用 ripgrep 查找任务
  M.find_tasks_with_ripgrep(vault_path, filter, use_float, group_by)
end

-- 使用 vim.loop 和 ripgrep 查找任务
function M.find_tasks_with_ripgrep(vault_path, query, use_float, group_by)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local handle
  local tasks = {}
  group_by = group_by or {}

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

  -- 按分组对任务进行排序和分组
  local function group_tasks(tasks, group_by)
    if #group_by == 0 then
      return {default = tasks}
    end

    -- 按照给定的分组依据创建分组
    local grouped = {}

    -- 递归函数，用于处理多级分组
    local function process_groups(current_tasks, group_index, prefix)
      prefix = prefix or {}
      local current_group = group_by[group_index]

      if not current_group then
        -- 已经处理完所有分组层级，将任务添加到结果中
        local key = table.concat(prefix, ":")
        if key == "" then key = "default" end
        grouped[key] = current_tasks
        return
      end

      -- 按当前分组类型对任务进行分组
      local sub_groups = {}
      for _, task in ipairs(current_tasks) do
        local group_value

        if current_group == "status" then
          group_value = (task.status == "[ ]") and "Pending" or "Completed"
        elseif current_group == "priority" then
          group_value = task.priority:sub(1, 1):upper() .. task.priority:sub(2)
        else
          group_value = "Other"
        end

        sub_groups[group_value] = sub_groups[group_value] or {}
        table.insert(sub_groups[group_value], task)
      end

      -- 递归处理下一级分组
      for sub_name, sub_tasks in pairs(sub_groups) do
        local new_prefix = vim.deepcopy(prefix)
        table.insert(new_prefix, sub_name)
        process_groups(sub_tasks, group_index + 1, new_prefix)
      end
    end

    process_groups(tasks, 1)
    return grouped
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
        -- 对任务按分组进行处理
        local grouped_tasks = group_tasks(filtered_tasks, group_by)

        if use_float then
          M.display_tasks_float(filtered_tasks, grouped_tasks)
        else
          M.display_tasks(filtered_tasks, grouped_tasks)
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

          -- 清理任务文本
          local clean_text = task_text:gsub("^%s*- %[.?%]", "")

          -- 提取优先级
          local priority = extract_priority(clean_text)

          -- 创建任务对象
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


-- 从显示行解析任务信息
local function parse_display_line(line)
  local index, status, rest = line:match("^(%d+)%. (%[.?%]) (.+)")

  if not (index and status and rest) then
    return nil
  end

  -- 提取优先级（如果有）
  local priority = "normal"
  local text = rest

  -- 检查是否有优先级标签
  local priority_match = rest:match("^%[([%w]+)%] (.+)")
  if priority_match then
    local priority_tag = priority_match:upper()
    if priority_tag == "HIGHEST" or 
      priority_tag == "HIGH" or 
      priority_tag == "MEDIUM" or 
      priority_tag == "LOW" or 
      priority_tag == "LOWEST" then
      priority = priority_tag:lower()
      text = rest:match("^%[([%w]+)%] (.+)")
    end
  end

  -- 提取文件路径和行号
  local file_path, line_number
  text, file_path, line_number = text:match("(.+) <!%-%- (.+):(%d+) %-%->$")

  if not (text and file_path and line_number) then
    return nil
  end

  return {
    index = tonumber(index),
    status = status,
    text = text,
    file_path = file_path,
    line_number = tonumber(line_number),
    priority = priority
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

  -- 替换状态，保留其他格式
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
    if line:match("^%d+%. %[.?%]") then  -- 确保是任务行，不是组标题
      local parsed = parse_display_line(line)
      if parsed and parsed.index and tasks[parsed.index] then
        local original_task = tasks[parsed.index]

        -- 检查是否有修改
        if original_task.status ~= parsed.status then
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

  vim.keymap.set({ 'n' }, 's', M.save_current_tasks, { buffer = buf, noremap = true, silent = true })

  -- 切换任务状态
  vim.keymap.set({'n'}, '<space>', M.toggle_task_at_cursor, { noremap = true, silent = true, buffer = buf })
end

-- 添加这个新函数来保存当前缓冲区的任务
function M.save_current_tasks()
  local buf = vim.api.nvim_get_current_buf()

  -- 获取与此缓冲区关联的任务列表
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
function M.display_tasks(tasks, grouped_tasks)
  -- 创建一个新的 buffer
  local buf = vim.api.nvim_create_buf(true, false) -- 创建正常的 buffer

  -- 存储任务列表与缓冲区的关联
  M.buffer_tasks[buf] = tasks

  -- 格式化任务显示
  local display_lines
  if grouped_tasks then
    display_lines, M.task_index_map = format_grouped_tasks(grouped_tasks)
  else
    display_lines = {}
    for i, task in ipairs(tasks) do
      table.insert(display_lines, format_task_for_display(task, i))
      M.task_index_map = M.task_index_map or {}
      M.task_index_map[i] = task
    end
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
      M.task_index_map = nil
    end,
    once = true
  })
end

-- 在浮动窗口中显示可编辑的任务列表
function M.display_tasks_float(tasks, grouped_tasks)
  -- 创建一个新的 buffer
  local buf = vim.api.nvim_create_buf(false, false)

  -- 存储任务列表与缓冲区的关联
  M.buffer_tasks[buf] = tasks

  -- 格式化任务显示
  local display_lines
  if grouped_tasks then
    display_lines, M.task_index_map = format_grouped_tasks(grouped_tasks)
  else
    display_lines = {}
    for i, task in ipairs(tasks) do
      table.insert(display_lines, format_task_for_display(task, i))
      M.task_index_map = M.task_index_map or {}
      M.task_index_map[i] = task
    end
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
      M.task_index_map = nil
    end,
    once = true
  })
end

-- 切换当前行任务的状态
function M.toggle_task_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(buf, row-1, row, false)[1]

  -- 跳过组标题行
  if line:match("^## ") then
    return
  end

  local parsed = parse_display_line(line)
  if parsed then
    -- 切换状态
    if parsed.status == "[ ]" then
      parsed.status = "[x]"
    else
      parsed.status = "[ ]"
    end

    -- 更新行
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

-- 设置模块
function M.setup(config)
  -- 获取用户配置
  config = config or {}
  local vault_path = config.vault_path or "/Users/didi/Notes"

  -- 注册树形语法解析器
  vim.treesitter.language.register("markdown", "obstasks")
end

return M
