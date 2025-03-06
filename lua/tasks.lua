local M = {}
-- 使用 vim.loop 和 ripgrep 查找任务
function M.find_tasks_with_ripgrep(vault_path, query, use_float)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local handle
  local output_data = {}

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
        include = task:match("%[ %]")
      elseif filters.done then
        include = not task:match("%[ %]")
      end
      if include and filters.due_date then
        include = task:match("📅 " .. filters.due_date)
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
    local filtered_tasks = filter_tasks(output_data, filters)

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
    args = { '\\- \\[.\\].*#t', vault_path },
    stdio = { nil, stdout, stderr }
  }, vim.schedule_wrap(on_exit))

  vim.loop.read_start(stdout, function(err, data)
    assert(not err, err)
    if data then
      -- 按行分割数据并存储到 output_data
      for line in data:gmatch("[^\r\n]+") do
        -- 提取任务和文件路径
        local file_path, task = line:match("^(%S+):(.+)$")
        if task and file_path then
          -- 将任务和文件路径组合并存储
          table.insert(output_data, task .. " [[" .. file_path .. "]]")
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

-- 设置 buffer 的公共属性
local function setup_buffer(buf)
  -- 设置 buffer 的选项
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf }) -- 设置为只读
  vim.api.nvim_set_option_value('filetype', 'obstasks', { buf = buf }) -- 设置自定义的 filetype

  -- 绑定 q 键来关闭 buffer
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })
end

-- 显示任务列表在一个新的 buffer 中
function M.display_tasks(tasks)
  -- 创建一个新的 buffer
  local buf = vim.api.nvim_create_buf(true, true) -- 不列入 buffer 列表，临时 buffer

  -- 设置 buffer 的内容
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, tasks)

  -- 设置 buffer 的共享属性
  setup_buffer(buf)

  -- 打开一个新的窗口并设置为当前 buffer
  vim.api.nvim_set_current_buf(buf)
end

-- 在浮动窗口中显示任务列表
function M.display_tasks_float(tasks)
  -- 创建一个新的 buffer
  local buf = vim.api.nvim_create_buf(false, true)

  vim.notify("buf id: " .. vim.inspect(buf))

  -- 设置 buffer 的内容
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, tasks)

  -- 设置 buffer 的共享属性
  setup_buffer(buf)

  -- 计算窗口大小和位置
  local width = math.max(80, math.floor(vim.o.columns * 0.8))
  local height = math.min(#tasks + 2, vim.o.lines - 4)
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

  -- 创建自动命令，当用户按 q 或者离开缓冲区时关闭窗口
  vim.api.nvim_create_autocmd({"BufLeave"}, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
    once = true
  })
end

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
