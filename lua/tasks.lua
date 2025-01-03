local M = {}

-- 使用 vim.loop 和 ripgrep 查找任务
function M.find_tasks_with_ripgrep(vault_path)
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)

    local handle
    local output_data = {}

    local function on_exit()
        stdout:close()
        stderr:close()
        handle:close()

        -- 如果没有输出数据，通知用户
        if #output_data == 0 then
            vim.schedule(function()
                vim.notify("No tasks found in the vault.", vim.log.levels.INFO)
            end)
        else
            vim.schedule(function()
                M.display_tasks(output_data)
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

-- 显示任务列表在一个新的 buffer 中
function M.display_tasks(tasks)
    -- 创建一个新的 buffer
    local buf = vim.api.nvim_create_buf(true, true) -- 不列入 buffer 列表，临时 buffer

    -- 设置 buffer 的内容
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, tasks)

    -- 设置 buffer 的选项
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false) -- 设置为只读

    -- 打开一个新的窗口并设置为当前 buffer
    vim.api.nvim_set_current_buf(buf)

    -- 绑定 q 键来关闭 buffer
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })
end

function M.setup()
    vim.api.nvim_create_user_command('FindTasksInVault', function()
        local vault_path = "/Users/didi/Notes"  -- 替换为你的 vault 路径
        M.find_tasks_with_ripgrep(vault_path)
    end, {})
end

return M 
