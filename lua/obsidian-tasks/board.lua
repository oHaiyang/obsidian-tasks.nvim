local M = {}

M.state = {}
M.DEFAULT_MAPPINGS = {
	close = "q",
	refresh = "<C-r>",
	query_source = "gq",
	show_query = "K",
	help = "?",
	task_source = { "gd", "gf" },
	toggle = "<Space>",
	status = "s",
	postpone = "p",
	edit = "e",
	next_task = "]t",
	previous_task = "[t",
}
M.BOARD_HELP_LINES = {}

local MAPPING_DESCRIPTIONS = {
	close = "Close tasks board",
	refresh = "Refresh tasks board",
	query_source = "Go to query source",
	show_query = "Show source query",
	help = "Show board help",
	task_source = "Go to task source",
	toggle = "Toggle task status",
	status = "Change task status",
	postpone = "Postpone task",
	edit = "Edit task",
	next_task = "Jump to next task",
	previous_task = "Jump to previous task",
}

local MAPPING_HELP = {
	{ "help", "Show or close this help" },
	{ "close", "Close board" },
	{ "refresh", "Refresh board from disk" },
	{ "show_query", "Show source query for current rendered section" },
	{ "query_source", "Jump to source ```tasks query block" },
	{ "task_source", "Jump to source task line" },
	{ "toggle", "Toggle task status" },
	{ "status", "Select task status" },
	{ "postpone", "Postpone task" },
	{ "edit", "Edit task in a form" },
	{ "next_task", "Jump to next rendered task" },
	{ "previous_task", "Jump to previous rendered task" },
}

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function clone_mapping(value)
	if type(value) ~= "table" then
		return value
	end
	return vim.deepcopy(value)
end

local function configured_mappings()
	local config = get_config()
	local custom = (type(config.board) == "table" and (config.board.mappings or config.board.keymaps or config.board.key_maps))
		or config.board_mappings
		or config.board_keymaps
		or config.boardMappings
		or config.boardKeymaps

	local mappings = {}
	for key, value in pairs(M.DEFAULT_MAPPINGS) do
		mappings[key] = clone_mapping(value)
	end
	if type(custom) == "table" then
		for key, value in pairs(custom) do
			mappings[key] = clone_mapping(value)
		end
	end
	return mappings
end

local function mapping_list(value)
	if value == false or value == nil or value == "" then
		return {}
	end
	if type(value) == "table" then
		local items = {}
		for _, item in ipairs(value) do
			if type(item) == "string" and item ~= "" then
				table.insert(items, item)
			end
		end
		return items
	end
	return { tostring(value) }
end

local function mapping_label(value)
	local items = mapping_list(value)
	if #items == 0 then
		return nil
	end
	return table.concat(items, " / ")
end

local function set_board_mapping(buf, mappings, key, callback)
	for _, lhs in ipairs(mapping_list(mappings[key])) do
		vim.keymap.set("n", lhs, callback, {
			buffer = buf,
			noremap = true,
			silent = true,
			desc = MAPPING_DESCRIPTIONS[key],
		})
	end
end

function M.board_help_lines()
	local mappings = configured_mappings()
	local parts = {}
	for _, item in ipairs({
		{ "help", "help" },
		{ "close", "close" },
		{ "refresh", "refresh" },
		{ "show_query", "query" },
		{ "query_source", "query source" },
		{ "task_source", "task source" },
		{ "toggle", "toggle" },
		{ "status", "status" },
		{ "postpone", "postpone" },
		{ "edit", "edit" },
		{ "next_task", "next task" },
		{ "previous_task", "previous task" },
	}) do
		local lhs = mapping_label(mappings[item[1]])
		if lhs then
			table.insert(parts, lhs .. " " .. item[2])
		end
	end
	local help_label = mapping_label(mappings.help) or "help"
	return {
		"> [" .. help_label .. "] Board keys: " .. table.concat(parts, " | "),
		"",
	}
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

local function slug(value)
	return tostring(value or "board"):gsub("[^%w_%-%./:]+", "_")
end

local function stable_hash(value)
	if vim.fn and vim.fn.sha256 then
		return vim.fn.sha256(tostring(value or "")):sub(1, 12)
	end

	local text = tostring(value or "")
	local hash = 5381
	for index = 1, #text do
		hash = ((hash * 33) + text:byte(index)) % 4294967296
	end
	return string.format("%08x", hash)
end

local function buffer_name(path)
	return string.format("obsidian-tasks://board/%s-%s", slug(path), stable_hash(path))
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
	if type(path) ~= "string" or type(vault_path) ~= "string" then
		return false
	end
	return path == vault_path or path:sub(1, #vault_path + 1) == vault_path .. "/"
end

local function display_path(path)
	local vault_path = normalize(get_config().vault_path)
	path = normalize(path)
	if type(path) == "string" and type(vault_path) == "string" and inside_vault(path, vault_path) then
		return path:sub(#vault_path + 2)
	end
	if vim.fn and vim.fn.fnamemodify then
		return vim.fn.fnamemodify(path, ":~:.")
	end
	return tostring(path or "")
end

local function resolve_path(path)
	local vault_path = ensure_vault_path()
	if not vault_path then
		return nil
	end

	path = trim(path)
	if not path or path == "" then
		local current = vim.api.nvim_buf_get_name(0)
		if is_markdown(current) and inside_vault(current, vault_path) then
			return normalize(current)
		end
		return nil, "pick"
	end

	local cwd_resolved = vim.fn and vim.fn.fnamemodify(path, ":p") or nil
	local candidates = {
		normalize(path),
		cwd_resolved and normalize(cwd_resolved) or nil,
		normalize(join_path(vault_path, path)),
	}

	local resolved
	for _, candidate in ipairs(candidates) do
		if inside_vault(candidate, vault_path) then
			resolved = candidate
			break
		end
	end

	if not resolved then
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
		if inside_vault(path, vault_path) and #require("obsidian-tasks.query_block").scan_file(path) > 0 then
			table.insert(result, path)
		end
	end
	return result
end

local function section_title(source)
	if source.name and source.name ~= "" and not source.unnamed then
		return source.name
	end
	return ""
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

local function heading_marker(level)
	level = tonumber(level) or 2
	if level < 1 then
		level = 1
	elseif level > 6 then
		level = 6
	end
	return string.rep("#", level)
end

local function copy_task(task)
	local copy = {}
	for key, value in pairs(task or {}) do
		copy[key] = value
	end
	return copy
end

local function copy_tasks(tasks)
	local copied = {}
	for _, task in ipairs(tasks or {}) do
		table.insert(copied, copy_task(task))
	end
	return copied
end

local function execute_source(source, opts)
	opts = opts or {}
	local config = get_config()
	local query = require("obsidian-tasks.query")
	local display = require("obsidian-tasks.display")
	local sorter = require("obsidian-tasks.sort")
	local cache = require("obsidian-tasks.cache")
	local title = section_title(source)
	local section_heading_level = (source.heading_level or 1) + 1
	local group_heading_level = title ~= "" and section_heading_level + 1 or section_heading_level

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
		local lines = {}
		if title ~= "" then
			table.insert(lines, heading_marker(section_heading_level) .. " " .. title)
		end
		table.insert(lines, "Query errors:")
		for _, err in ipairs(plan.errors) do
			table.insert(lines, string.format("- line %s: %s", err.line_number or err.line or "?", err.message or "Unknown query error"))
			if err.instruction and err.instruction ~= "" then
				table.insert(lines, "  instruction: " .. err.instruction)
			end
		end
		return lines, {}, opts.start_index or 1, plan
	end

	local tasks = opts.tasks
	if not tasks and opts.get_tasks then
		tasks = opts.get_tasks()
	end
	tasks = tasks or cache.tasks({
		vault_path = config.vault_path,
		global_filter = config.global_filter,
		remove_global_filter = config.remove_global_filter,
		today = opts.today,
		use_cache = opts.use_cache or opts.useCache,
	})
	local filtered = query.filter_tasks(tasks, plan, config)
	if #plan.sorts > 0 then
		filtered = sorter.apply(filtered, plan.sorts, config)
	end

	local total_count = #filtered
	filtered = apply_limit(filtered, plan.limit)
	local board_tasks = copy_tasks(filtered)

	return display.format_task_result_section(board_tasks, {
		section_title = title,
		section_heading_level = section_heading_level,
		query_plan = plan,
		layout = plan.layout,
		group_by = plan.group_by,
		status_config = config,
		group_heading_level = group_heading_level,
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

local function prefix_lines(lines, prefix)
	if not prefix or prefix == "" then
		return lines
	end
	local prefixed = {}
	for _, line in ipairs(lines or {}) do
		table.insert(prefixed, prefix .. line)
	end
	return prefixed
end

local function build_board_lines(path, source_lines, opts)
	opts = opts or {}
	local query_block = require("obsidian-tasks.query_block")
	local cache = require("obsidian-tasks.cache")
	local config = get_config()
	local sources = query_block.scan_lines(source_lines, path)
	local lines = {}
	for _, line in ipairs(M.board_help_lines()) do
		table.insert(lines, line)
	end
	local sections = {}
	local index_map = {}
	local next_source_line = 1
	local next_task_index = 1
	local shared_tasks = opts.tasks
	local function get_tasks()
		if not shared_tasks then
			shared_tasks = cache.tasks({
				vault_path = config.vault_path,
				global_filter = config.global_filter,
				remove_global_filter = config.remove_global_filter,
				today = opts.today,
				use_cache = opts.use_cache or opts.useCache,
			})
		end
		return shared_tasks
	end

	for _, source in ipairs(sources) do
		for line_number = next_source_line, source.source_line - 1 do
			table.insert(lines, source_lines[line_number] or "")
		end

		local render_start = #lines + 1
		local section_lines, section_index_map, next_index = execute_source(source, {
			start_index = next_task_index,
			today = opts.today,
			use_cache = opts.use_cache,
			useCache = opts.useCache,
			tasks = opts.tasks,
			get_tasks = get_tasks,
		})
		section_lines = prefix_lines(section_lines, source.quote_prefix)
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
		local insert_at = #M.board_help_lines() + 1
		table.insert(lines, insert_at, "> No tasks query blocks found")
		table.insert(lines, insert_at + 1, "")
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

local function row_has_rendered_task(buf, row)
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	local parsed = require("obsidian-tasks.parser").parse_display_line(line)
	return parsed and parsed.index and (require("obsidian-tasks.core").task_index_map[buf] or {})[parsed.index] ~= nil
end

function M.jump_task(opts)
	opts = opts or {}
	local buf = opts.buffer or vim.api.nvim_get_current_buf()
	if not M.is_board_buffer(buf) then
		return false
	end
	local direction = opts.direction or 1
	local current = vim.api.nvim_win_get_cursor(0)[1]
	local line_count = vim.api.nvim_buf_line_count(buf)
	local row = current + direction
	while row >= 1 and row <= line_count do
		if row_has_rendered_task(buf, row) then
			pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
			return true
		end
		row = row + direction
	end
	return false
end

local function setup_keymaps(buf)
	local mappings = configured_mappings()

	set_board_mapping(buf, mappings, "close", function()
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end)

	set_board_mapping(buf, mappings, "refresh", function()
		M.refresh({ buffer = buf })
	end)

	set_board_mapping(buf, mappings, "query_source", function()
		M.go_to_query_source({ buffer = buf })
	end)

	set_board_mapping(buf, mappings, "show_query", function()
		M.show_query({ buffer = buf })
	end)

	set_board_mapping(buf, mappings, "help", function()
		M.show_help({ buffer = buf })
	end)

	set_board_mapping(buf, mappings, "task_source", function()
		M.go_to_task_source({ buffer = buf })
	end)

	set_board_mapping(buf, mappings, "toggle", require("obsidian-tasks").toggle_task_at_cursor)

	set_board_mapping(buf, mappings, "postpone", function()
		require("obsidian-tasks").postpone_task_at_cursor()
	end)

	set_board_mapping(buf, mappings, "edit", function()
		require("obsidian-tasks").edit_current_task()
	end)

	set_board_mapping(buf, mappings, "status", function()
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
	end)

	set_board_mapping(buf, mappings, "next_task", function()
		M.jump_task({ buffer = buf, direction = 1 })
	end)

	set_board_mapping(buf, mappings, "previous_task", function()
		M.jump_task({ buffer = buf, direction = -1 })
	end)
end

local function open_resolved_path(path)
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
				local core = require("obsidian-tasks.core")
				core.task_index_map[buf] = nil
				core.buffer_tasks[buf] = nil
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

function M.open_path(path)
	local resolved, mode = resolve_path(path)
	if mode == "pick" then
		vim.notify("obsidian-tasks.nvim: board path is required", vim.log.levels.ERROR)
		return nil
	end
	if not resolved then
		return nil
	end
	return open_resolved_path(resolved)
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
				local resolved = resolve_path(choice)
				if resolved then
					open_resolved_path(resolved)
				end
			end
		end)
		return nil
	end
	if not path then
		return nil
	end
	return open_resolved_path(path)
end

local function section_at_row(state, row)
	for _, section in ipairs(state.sections or {}) do
		if row >= section.render_start and row <= section.render_end then
			return section
		end
	end
	return nil
end

local function query_hover_lines(source)
	local lines = {
		"Tasks query",
		string.format("%s:%d", display_path(source.source_path), source.source_line or 1),
		"",
		"```tasks",
	}
	for _, line in ipairs(vim.split(source.query or "", "\n", { plain = true })) do
		table.insert(lines, line)
	end
	table.insert(lines, "```")
	return lines
end

local function max_display_width(lines)
	local width = 0
	for _, line in ipairs(lines or {}) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end
	return width
end

local function close_query_float()
	local float = M.query_float
	M.query_float = nil
	if float and float.autocmd then
		pcall(vim.api.nvim_del_autocmd, float.autocmd)
	end
	if float and float.win and vim.api.nvim_win_is_valid(float.win) then
		pcall(vim.api.nvim_win_close, float.win, true)
	end
	if float and float.buf and vim.api.nvim_buf_is_valid(float.buf) then
		pcall(vim.api.nvim_buf_delete, float.buf, { force = true })
	end
end

local function open_query_float(lines, source, source_buf)
	close_query_float()
	if not source_buf or source_buf == 0 then
		source_buf = vim.api.nvim_get_current_buf()
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	local columns = math.max(vim.o.columns or 80, 24)
	local rows = math.max((vim.o.lines or 24) - (vim.o.cmdheight or 1) - 4, 1)
	local width = math.min(math.max(max_display_width(lines), 24), math.max(columns - 4, 24))
	local height = math.min(#lines, rows)
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = true,
	})
	pcall(vim.api.nvim_set_option_value, "wrap", false, { win = win })

	local function close()
		close_query_float()
	end
	vim.keymap.set("n", "q", close, { buffer = buf, noremap = true, silent = true, nowait = true, desc = "Close query hover" })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, noremap = true, silent = true, nowait = true, desc = "Close query hover" })

	M.query_float = {
		buf = buf,
		buffer = buf,
		win = win,
		window = win,
		lines = lines,
		source = source,
		source_buf = source_buf,
	}
	if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
		M.query_float.autocmd = vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "WinLeave" }, {
			buffer = source_buf,
			once = true,
			callback = function()
				close_query_float()
			end,
		})
	end
	return M.query_float
end

local function board_help_float_lines()
	local mappings = configured_mappings()
	local lines = {
		"Tasks board keymaps",
		"",
	}
	for _, item in ipairs(MAPPING_HELP) do
		local lhs = mapping_label(mappings[item[1]])
		if lhs then
			table.insert(lines, string.format("%-12s %s", lhs, item[2]))
		end
	end
	table.insert(lines, "")
	table.insert(lines, "Task actions only work on rendered task rows. Markdown remains read-only.")
	return lines
end

local function close_help_float()
	local float = M.help_float
	M.help_float = nil
	if float and float.autocmd then
		pcall(vim.api.nvim_del_autocmd, float.autocmd)
	end
	if float and float.win and vim.api.nvim_win_is_valid(float.win) then
		pcall(vim.api.nvim_win_close, float.win, true)
	end
	if float and float.buf and vim.api.nvim_buf_is_valid(float.buf) then
		pcall(vim.api.nvim_buf_delete, float.buf, { force = true })
	end
end

local function open_help_float(source_buf)
	if M.help_float then
		close_help_float()
		return nil
	end
	close_query_float()
	if not source_buf or source_buf == 0 then
		source_buf = vim.api.nvim_get_current_buf()
	end
	local lines = board_help_float_lines()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	local columns = math.max(vim.o.columns or 80, 24)
	local rows = math.max((vim.o.lines or 24) - (vim.o.cmdheight or 1) - 4, 1)
	local width = math.min(math.max(max_display_width(lines), 32), math.max(columns - 4, 24))
	local height = math.min(#lines, rows)
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = false,
	})
	pcall(vim.api.nvim_set_option_value, "wrap", false, { win = win })

	M.help_float = {
		buf = buf,
		buffer = buf,
		win = win,
		window = win,
		lines = lines,
		source_buf = source_buf,
	}
	if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
		M.help_float.autocmd = vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "BufDelete" }, {
			buffer = source_buf,
			once = true,
			callback = function()
				close_help_float()
			end,
		})
	end
	return M.help_float
end

function M.show_help(opts)
	opts = opts or {}
	local buf = opts.buffer or opts.buf
	if not buf or buf == 0 then
		buf = vim.api.nvim_get_current_buf()
	end
	if not M.is_board_buffer(buf) then
		vim.notify("obsidian-tasks.nvim: current buffer is not a board", vim.log.levels.WARN)
		return nil
	end
	return open_help_float(buf)
end

local function navigation_buffer(opts)
	local current = vim.api.nvim_get_current_buf()
	local requested = opts and (opts.buffer or opts.buf)
	if requested and requested ~= 0 and requested ~= current then
		vim.notify("obsidian-tasks.nvim: board navigation requires the target board to be the current buffer", vim.log.levels.WARN)
		return nil
	end
	return current
end

function M.query_at_cursor(opts)
	opts = opts or {}
	local buf = navigation_buffer(opts)
	if not buf then
		return nil
	end
	local state = state_for(buf)
	if not state then
		vim.notify("obsidian-tasks.nvim: current buffer is not a board", vim.log.levels.WARN)
		return nil
	end
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local section = section_at_row(state, row)
	if not section or not section.source then
		vim.notify("obsidian-tasks.nvim: no tasks query under cursor", vim.log.levels.WARN)
		return nil
	end
	return section.source, section
end

function M.show_query(opts)
	opts = opts or {}
	local source_buf = opts.buffer or opts.buf
	if not source_buf or source_buf == 0 then
		source_buf = vim.api.nvim_get_current_buf()
	end
	local source = M.query_at_cursor(opts)
	if not source then
		close_query_float()
		return nil
	end
	return open_query_float(query_hover_lines(source), source, source_buf)
end

function M.go_to_query_source(opts)
	opts = opts or {}
	local buf = navigation_buffer(opts)
	if not buf then
		return false
	end
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
	local parsed = require("obsidian-tasks.parser").parse_display_line(vim.api.nvim_get_current_line())
	return parsed and parsed.index and (require("obsidian-tasks.core").task_index_map[buf] or {})[parsed.index] or nil
end

function M.go_to_task_source(opts)
	opts = opts or {}
	local buf = navigation_buffer(opts)
	if not buf then
		return false
	end
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
