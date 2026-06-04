local M = {}

M.state = {}

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function realpath(path)
	if not path or path == "" then
		return path
	end
	local uv = vim.uv or vim.loop
	return (uv and uv.fs_realpath(path)) or path
end

local function normalize(path)
	path = realpath(path) or path
	if type(path) == "string" then
		return path:gsub("/+$", "")
	end
	return path
end

local function join_path(root, child)
	if not child or child == "" then
		return root
	end
	if child:sub(1, 1) == "/" then
		return child
	end
	if vim.fs and vim.fs.joinpath then
		return vim.fs.joinpath(root, child)
	end
	return root:gsub("/+$", "") .. "/" .. child
end

local function read_lines(path)
	local file = io.open(path, "r")
	if not file then
		return nil, "Cannot open file: " .. tostring(path)
	end
	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()
	return lines
end

local function is_markdown(path)
	return type(path) == "string" and path:sub(-3) == ".md"
end

local function basename(path)
	return (path or ""):match("([^/]+)$") or path or ""
end

local function slug(value)
	return tostring(value or "board"):gsub("[^%w_%-%./:]+", "_")
end

local function buffer_name(path)
	return "obsidian-tasks://board/" .. slug(path)
end

local function buffer_name_exists(name)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
			return buf
		end
	end
	return nil
end

local function ensure_vault_path()
	local vault_path = normalize(get_config().vault_path)
	if not vault_path or vault_path == "" then
		vim.notify("obsidian-tasks.nvim: vault_path is required to open a board", vim.log.levels.ERROR)
		return nil
	end
	return vault_path
end

local function inside_vault(path, vault_path)
	path = normalize(path)
	vault_path = normalize(vault_path)
	if not path or not vault_path then
		return false
	end
	return path == vault_path or path:sub(1, #vault_path + 1) == vault_path .. "/"
end

local function resolve_path(path)
	local vault_path = ensure_vault_path()
	if not vault_path then
		return nil
	end

	if not path or path == "" then
		local current = vim.api.nvim_buf_get_name(0)
		if is_markdown(current) and inside_vault(current, vault_path) then
			return normalize(current)
		end
		return nil, "pick"
	end

	local resolved = normalize(path)
	if not inside_vault(resolved, vault_path) then
		resolved = normalize(join_path(vault_path, path))
	end
	if not inside_vault(resolved, vault_path) then
		vim.notify("obsidian-tasks.nvim: board file must be inside vault_path: " .. tostring(path), vim.log.levels.ERROR)
		return nil
	end
	if not is_markdown(resolved) then
		vim.notify("obsidian-tasks.nvim: board file must be a markdown file: " .. tostring(path), vim.log.levels.ERROR)
		return nil
	end
	return resolved
end

local function markdown_files_with_queries(vault_path)
	local pattern = vim.fs and vim.fs.joinpath and vim.fs.joinpath(vault_path, "**", "*.md")
		or (vault_path:gsub("/$", "") .. "/**/*.md")
	local files = vim.fn.glob(pattern, false, true)
	table.sort(files)
	local result = {}
	for _, path in ipairs(files) do
		if #require("obsidian-tasks.query_block").scan_file(path) > 0 then
			table.insert(result, path)
		end
	end
	return result
end

local function section_title(source)
	if source.name and source.name ~= "" and not source.unnamed then
		return source.name
	end
	return string.format("Tasks query at %s#L%d", basename(source.source_path), source.source_line or 1)
end

local function apply_limit(tasks, limit)
	if not limit or limit <= 0 or #tasks <= limit then
		return tasks
	end
	local limited = {}
	for index = 1, limit do
		table.insert(limited, tasks[index])
	end
	return limited
end

local function execute_source(source, opts)
	opts = opts or {}
	local config = get_config()
	local query = require("obsidian-tasks.query")
	local display = require("obsidian-tasks.display")
	local sorter = require("obsidian-tasks.sort")
	local cache = require("obsidian-tasks.cache")

	local query_opts = {
		today = opts.today,
		config = config,
		enable_lua_filters = config.enable_lua_filters or config.enableLuaFilters,
		query_source = source,
		query_file_path = source.source_path,
		source_path = source.source_path,
	}
	local composition = query.compose(source.query, query_opts)
	local plan = query.parse(composition.source, query_opts)
	plan.composition = composition
	plan.original_query = source.query

	if #plan.errors > 0 then
		local lines = { "## " .. section_title(source), "Query errors:" }
		for _, err in ipairs(plan.errors) do
			table.insert(lines, string.format("- line %s: %s", err.line or "?", err.message or "Unknown query error"))
			if err.instruction and err.instruction ~= "" then
				table.insert(lines, "  instruction: " .. err.instruction)
			end
		end
		return lines, {}, opts.start_index or 1, plan
	end

	local tasks = cache.tasks({
		vault_path = config.vault_path,
		global_filter = config.global_filter,
		remove_global_filter = config.remove_global_filter,
		today = opts.today,
		use_cache = opts.use_cache or opts.useCache,
	})
	local filtered = query.filter_tasks(tasks, plan)
	if #plan.sorts > 0 then
		filtered = sorter.apply(filtered, plan.sorts)
	end

	local total_count = #filtered
	filtered = apply_limit(filtered, plan.limit)

	return display.format_task_result_section(filtered, {
		section_title = section_title(source),
		query_plan = plan,
		layout = plan.layout,
		group_by = plan.group_by,
		hierarchical_headings = config.display and config.display.hierarchical_headings or false,
		total_count = total_count,
		limit = plan.limit,
		start_index = opts.start_index or 1,
	})
end

local function merge_index_map(target, source)
	for index, task in pairs(source or {}) do
		target[index] = task
	end
end

local function build_board_lines(path, source_lines)
	local query_block = require("obsidian-tasks.query_block")
	local sources = query_block.scan_lines(source_lines, path)
	local lines = {}
	local sections = {}
	local index_map = {}
	local next_source_line = 1
	local next_task_index = 1

	for _, source in ipairs(sources) do
		for line_number = next_source_line, source.source_line - 1 do
			table.insert(lines, source_lines[line_number] or "")
		end

		local render_start = #lines + 1
		local section_lines, section_index_map, next_index = execute_source(source, {
			start_index = next_task_index,
		})
		for _, line in ipairs(section_lines) do
			table.insert(lines, line)
		end
		merge_index_map(index_map, section_index_map)
		next_task_index = next_index
		table.insert(sections, {
			source = source,
			render_start = render_start,
			render_end = #lines,
		})

		next_source_line = source.end_line + 1
	end

	for line_number = next_source_line, #source_lines do
		table.insert(lines, source_lines[line_number] or "")
	end

	if #sources == 0 then
		table.insert(lines, 1, "> No tasks query blocks found")
		table.insert(lines, 2, "")
	end

	return lines, sections, index_map
end

local function configure_buffer(buf, path)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.b[buf].obsidian_tasks_board = true
	vim.b[buf].obsidian_tasks_board_source = path
end

local function set_buffer_lines(buf, lines)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_set_option_value("readonly", false, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modified", false, { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

local function state_for(buf)
	return M.state[buf or vim.api.nvim_get_current_buf()]
end

function M.is_board_buffer(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].obsidian_tasks_board == true
end

function M.refresh(opts)
	opts = opts or {}
	local buf = opts.buffer or opts.buf or vim.api.nvim_get_current_buf()
	local state = state_for(buf)
	if not state then
		vim.notify("obsidian-tasks.nvim: current buffer is not a board", vim.log.levels.ERROR)
		return false
	end

	local win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(win)
	local source_lines, err = read_lines(state.source_path)
	if not source_lines then
		vim.notify(err, vim.log.levels.ERROR)
		return false
	end
	local lines, sections, index_map = build_board_lines(state.source_path, source_lines)
	set_buffer_lines(buf, lines)
	M.state[buf] = {
		source_path = state.source_path,
		sections = sections,
	}
	require("obsidian-tasks.core").task_index_map[buf] = index_map
	require("obsidian-tasks.core").buffer_tasks[buf] = nil

	if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_buf() == buf then
		local row = math.min(cursor[1], vim.api.nvim_buf_line_count(buf))
		pcall(vim.api.nvim_win_set_cursor, win, { row, cursor[2] })
	end
	return true
end

local function setup_keymaps(buf)
	vim.keymap.set("n", "q", function()
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end, { buffer = buf, noremap = true, silent = true, desc = "Close tasks board" })

	vim.keymap.set("n", "<c-r>", function()
		M.refresh({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Refresh tasks board" })

	vim.keymap.set("n", "gq", function()
		M.go_to_query_source({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Go to query source" })

	vim.keymap.set({ "n" }, "gd", function()
		M.go_to_task_source({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Go to task source" })
	vim.keymap.set({ "n" }, "gf", function()
		M.go_to_task_source({ buffer = buf })
	end, { buffer = buf, noremap = true, silent = true, desc = "Go to task source" })

	vim.keymap.set({ "n" }, "<space>", require("obsidian-tasks").toggle_task_at_cursor, {
		buffer = buf,
		noremap = true,
		silent = true,
		desc = "Toggle task status",
	})
	vim.keymap.set("n", "s", function()
		local entries = require("obsidian-tasks.status").registry(require("obsidian-tasks").config or {})
		vim.ui.select(entries, {
			prompt = "Task status",
			format_item = function(entry)
				return string.format("[%s] %s (%s)", entry.symbol, entry.name, entry.type)
			end,
		}, function(entry)
			if entry then
				require("obsidian-tasks").change_task_status_at_cursor(entry.symbol)
			end
		end)
	end, { buffer = buf, noremap = true, silent = true, desc = "Change task status" })
	vim.keymap.set("n", "p", function()
		require("obsidian-tasks").postpone_task_at_cursor()
	end, { buffer = buf, noremap = true, silent = true, desc = "Postpone task" })
	vim.keymap.set("n", "e", function()
		require("obsidian-tasks").edit_current_task()
	end, { buffer = buf, noremap = true, silent = true, desc = "Edit task" })
end

function M.open_path(path)
	local source_lines, err = read_lines(path)
	if not source_lines then
		vim.notify(err, vim.log.levels.ERROR)
		return nil
	end
	local name = buffer_name(path)
	local buf = buffer_name_exists(name)
	if not buf then
		buf = vim.api.nvim_create_buf(true, false)
		pcall(vim.api.nvim_buf_set_name, buf, name)
		configure_buffer(buf, path)
		setup_keymaps(buf)
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = buf,
			once = true,
			callback = function()
				M.state[buf] = nil
				require("obsidian-tasks.core").task_index_map[buf] = nil
			end,
		})
	end

	local lines, sections, index_map = build_board_lines(path, source_lines)
	set_buffer_lines(buf, lines)
	M.state[buf] = {
		source_path = path,
		sections = sections,
	}
	require("obsidian-tasks.core").task_index_map[buf] = index_map
	require("obsidian-tasks.core").buffer_tasks[buf] = nil
	vim.api.nvim_set_current_buf(buf)
	return buf
end

function M.open(opts)
	opts = opts or {}
	if type(opts) == "string" then
		opts = { path = opts }
	end
	local path, mode = resolve_path(opts.path or opts.file or opts.file_path or opts.filePath or opts.name)
	if mode == "pick" then
		local vault_path = ensure_vault_path()
		if not vault_path then
			return nil
		end
		local files = markdown_files_with_queries(vault_path)
		if #files == 0 then
			vim.notify("obsidian-tasks.nvim: no markdown files with tasks query blocks found", vim.log.levels.WARN)
			return nil
		end
		vim.ui.select(files, {
			prompt = "Obsidian Tasks board",
			format_item = function(item)
				return item:gsub("^" .. vim.pesc(vault_path .. "/"), "")
			end,
		}, function(choice)
			if choice then
				M.open_path(choice)
			end
		end)
		return nil
	end
	if not path then
		return nil
	end
	return M.open_path(path)
end

local function section_at_row(state, row)
	for _, section in ipairs(state.sections or {}) do
		if row >= section.render_start and row <= section.render_end then
			return section
		end
	end
	return nil
end

function M.go_to_query_source(opts)
	opts = opts or {}
	local buf = opts.buffer or opts.buf or vim.api.nvim_get_current_buf()
	local state = state_for(buf)
	if not state then
		vim.notify("obsidian-tasks.nvim: current buffer is not a board", vim.log.levels.WARN)
		return false
	end
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local section = section_at_row(state, row)
	if not section or not section.source then
		vim.notify("obsidian-tasks.nvim: cursor is not in a rendered query section", vim.log.levels.WARN)
		return false
	end
	vim.cmd("edit +" .. section.source.source_line .. " " .. vim.fn.fnameescape(section.source.source_path))
	return true
end

local function task_at_cursor(buf)
	local line = vim.api.nvim_get_current_line()
	local index = tonumber(line:match("^%s*(%d+)%. "))
	return index and (require("obsidian-tasks.core").task_index_map[buf] or {})[index] or nil
end

function M.go_to_task_source(opts)
	opts = opts or {}
	local buf = opts.buffer or opts.buf or vim.api.nvim_get_current_buf()
	local task = task_at_cursor(buf)
	if not task then
		vim.notify("obsidian-tasks.nvim: cursor is not on a rendered task", vim.log.levels.WARN)
		return false
	end
	local located, locate_err = require("obsidian-tasks.source").locate_in_file(task)
	if not located then
		vim.notify(locate_err or "Task source line changed; refresh the board", vim.log.levels.WARN)
		return false
	end
	vim.cmd("edit +" .. located .. " " .. vim.fn.fnameescape(task.file_path))
	return true
end

function M.refresh_after_mutation(buf)
	if M.is_board_buffer(buf) then
		return M.refresh({ buffer = buf })
	end
	return false
end

return M
