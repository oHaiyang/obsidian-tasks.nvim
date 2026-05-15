local M = {}

M.last_query_name = nil

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function slug(value)
	return tostring(value or "query"):gsub("[^%w_%-%./:]+", "_")
end

local function active_buffer_name()
	return "obsidian-tasks://active"
end

local function pinned_buffer_name(source)
	return "obsidian-tasks://" .. slug(source.id or source.name)
end

local function normalize_source(id, value)
	if type(value) == "string" then
		return {
			id = id,
			name = id,
			query = value,
			source_type = "config",
		}
	elseif type(value) == "table" then
		return {
			id = value.id or id,
			name = value.name or value.id or id,
			query = value.query or value.text or "",
			source_type = value.source_type or "config",
			source_path = value.source_path,
			source_line = value.source_line,
		}
	end
	return nil
end

function M.get_sources()
	local config = get_config()
	local queries = config.queries or {}
	local sources = {}

	if #queries > 0 then
		for index, item in ipairs(queries) do
			local source = normalize_source(item.id or item.name or tostring(index), item)
			if source and source.query ~= "" then
				table.insert(sources, source)
			end
		end
	else
		for id, value in pairs(queries) do
			local source = normalize_source(id, value)
			if source and source.query ~= "" then
				table.insert(sources, source)
			end
		end
	end

	table.sort(sources, function(left, right)
		return tostring(left.name) < tostring(right.name)
	end)

	return sources
end

function M.complete_query_names()
	local names = {}
	for _, source in ipairs(M.get_sources()) do
		table.insert(names, source.id)
	end
	return names
end

function M.find_source(name)
	local sources = M.get_sources()
	if #sources == 0 then
		return nil, sources
	end

	if not name or name == "" then
		local config = get_config()
		name = M.last_query_name or config.default_query
	end

	if name and name ~= "" then
		for _, source in ipairs(sources) do
			if source.id == name or source.name == name then
				return source, sources
			end
		end
		return nil, sources
	end

	return sources[1], sources
end

local function run_source(source, opts)
	opts = opts or {}
	if not source then
		vim.notify("obsidian-tasks.nvim: query not found", vim.log.levels.ERROR)
		return
	end

	M.last_query_name = source.id

	local buffer_name = opts.buffer_name
	if not buffer_name then
		buffer_name = opts.pinned and pinned_buffer_name(source) or active_buffer_name()
	end

	local reuse_buffer = opts.reuse_buffer
	if reuse_buffer == nil then
		reuse_buffer = opts.buffer or true
	end

	return require("obsidian-tasks").find_tasks({
		query = source.query,
		query_name = source.name,
		query_source = source,
		buffer_name = buffer_name,
		reuse_buffer = reuse_buffer,
		pinned = opts.pinned or false,
		float = opts.float or false,
	})
end

function M.open(opts)
	opts = opts or {}
	if type(opts) == "string" then
		opts = { name = opts }
	end
	return M.open_query(opts.name, opts)
end

function M.open_query(name, opts)
	opts = opts or {}
	local source = M.find_source(name)
	if not source then
		if name and name ~= "" then
			vim.notify("obsidian-tasks.nvim: unknown query: " .. name, vim.log.levels.ERROR)
		else
			vim.notify("obsidian-tasks.nvim: no queries configured", vim.log.levels.ERROR)
		end
		return
	end
	return run_source(source, opts)
end

function M.run_query(query_text, opts)
	opts = opts or {}
	query_text = query_text or ""
	if query_text == "" then
		vim.notify("obsidian-tasks.nvim: query text is empty", vim.log.levels.ERROR)
		return
	end

	local source = {
		id = opts.id or "manual",
		name = opts.name or "manual",
		query = query_text,
		source_type = "manual",
	}
	return run_source(source, opts)
end

local function source_index(sources, id)
	for index, source in ipairs(sources) do
		if source.id == id or source.name == id then
			return index
		end
	end
	return 1
end

local function current_finder_opts(buf)
	local display = require("obsidian-tasks.display")
	return display.buffer_finder_opts[buf or vim.api.nvim_get_current_buf()] or {}
end

function M.select_query(opts)
	opts = opts or {}
	local buf = opts.buffer or vim.api.nvim_get_current_buf()
	local sources = M.get_sources()
	if #sources == 0 then
		vim.notify("obsidian-tasks.nvim: no queries configured", vim.log.levels.ERROR)
		return
	end

	vim.ui.select(sources, {
		prompt = "Obsidian Tasks query",
		format_item = function(source)
			return string.format("%s    %s", source.name, source.source_type or "config")
		end,
	}, function(source)
		if not source then
			return
		end
		local finder_opts = current_finder_opts(buf)
		run_source(source, {
			buffer = buf,
			buffer_name = finder_opts.buffer_name or vim.api.nvim_buf_get_name(buf),
			pinned = finder_opts.pinned,
		})
	end)
end

local function cycle_query(direction, opts)
	opts = opts or {}
	local buf = opts.buffer or vim.api.nvim_get_current_buf()
	local finder_opts = current_finder_opts(buf)
	local sources = M.get_sources()
	if #sources == 0 then
		vim.notify("obsidian-tasks.nvim: no queries configured", vim.log.levels.ERROR)
		return
	end

	local current = finder_opts.query_source and finder_opts.query_source.id or M.last_query_name
	local index = source_index(sources, current)
	index = index + direction
	if index > #sources then
		index = 1
	elseif index < 1 then
		index = #sources
	end

	run_source(sources[index], {
		buffer = buf,
		buffer_name = finder_opts.buffer_name or vim.api.nvim_buf_get_name(buf),
		pinned = finder_opts.pinned,
	})
end

function M.next_query(opts)
	return cycle_query(1, opts)
end

function M.previous_query(opts)
	return cycle_query(-1, opts)
end

function M.go_to_query_source(opts)
	opts = opts or {}
	local finder_opts = current_finder_opts(opts.buffer)
	local source = finder_opts.query_source
	if not source then
		vim.notify("obsidian-tasks.nvim: no query source for this buffer", vim.log.levels.WARN)
		return
	end

	if source.source_path and source.source_line then
		vim.cmd("edit +" .. source.source_line .. " " .. vim.fn.fnameescape(source.source_path))
		return
	end

	vim.notify("Query source: " .. (source.source_type or "manual"), vim.log.levels.INFO)
end

function M.setup_commands()
	vim.api.nvim_create_user_command("ObsidianTasks", function(command)
		M.open_query(command.args ~= "" and command.args or nil, {
			pinned = command.bang,
		})
	end, {
		nargs = "?",
		bang = true,
		force = true,
		complete = function()
			return M.complete_query_names()
		end,
	})

	vim.api.nvim_create_user_command("ObsidianTasksQuery", function(command)
		if command.args and command.args ~= "" then
			M.run_query(command.args, {
				name = "manual",
			})
			return
		end

		vim.ui.input({ prompt = "Tasks query: " }, function(input)
			if input and input ~= "" then
				M.run_query(input, {
					name = "manual",
				})
			end
		end)
	end, {
		nargs = "*",
		force = true,
	})
end

return M
