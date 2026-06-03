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
	return "obsidian-tasks://" .. slug(source.qualified_id or source.id or source.name)
end

function M.get_sources()
	return require("obsidian-tasks.query_registry").get_sources()
end

function M.complete_query_names()
	return require("obsidian-tasks.query_registry").complete_names()
end

function M.find_source(name)
	local registry = require("obsidian-tasks.query_registry")
	local source, sources
	source, sources = registry.find_source(name)
	if #sources == 0 then
		return nil, sources
	end

	if not name or name == "" then
		local config = get_config()
		name = M.last_query_name or config.default_query
	end

	if name and name ~= "" then
		return registry.find_source(name)
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
		query_file_path = opts.query_file_path or opts.queryFilePath,
		source_path = opts.source_path or opts.sourcePath,
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
		source_type = "recent",
		source_path = opts.source_path or opts.sourcePath or opts.query_file_path or opts.queryFilePath,
		source_line = opts.source_line or opts.sourceLine,
	}
	require("obsidian-tasks.query_registry").add_recent(source)
	return run_source(source, opts)
end

local function source_index(sources, id)
	for index, source in ipairs(sources) do
		if source.qualified_id == id or source.id == id or source.name == id then
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
			return require("obsidian-tasks.query_registry").format_source(source)
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

	local current = finder_opts.query_source
			and (finder_opts.query_source.qualified_id or finder_opts.query_source.id)
		or M.last_query_name
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

function M.refresh_queries(opts)
	opts = opts or {}
	local sources = require("obsidian-tasks.query_registry").refresh({
		vault_path = opts.vault_path,
	})
	vim.notify(string.format("Refreshed %d tasks query block(s)", #sources), vim.log.levels.INFO)
	return sources
end

function M.run_query_at_cursor(opts)
	opts = opts or {}
	local source = require("obsidian-tasks.query_block").find_at_cursor(opts.buffer, opts.row)
	if not source then
		vim.notify("obsidian-tasks.nvim: cursor is not inside a tasks query block", vim.log.levels.WARN)
		return
	end

	return run_source(source, {
		pinned = opts.pinned or false,
		float = opts.float or false,
	})
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

	vim.api.nvim_create_user_command("ObsidianTasksRefreshQueries", function()
		M.refresh_queries()
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksRefreshCache", function()
		local refreshed = require("obsidian-tasks").refresh_cache()
		vim.notify(string.format("Obsidian Tasks cache refreshed: %d task(s)", #refreshed), vim.log.levels.INFO)
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksClearCache", function()
		require("obsidian-tasks").clear_cache()
		vim.notify("Obsidian Tasks cache cleared", vim.log.levels.INFO)
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksCacheInfo", function()
		local stats = require("obsidian-tasks").cache_stats()
		local context = stats.context or {}
		local message = string.format(
			"Obsidian Tasks cache: %s, %d file(s), %d task(s)%s",
			stats.status or "cold",
			stats.file_count or 0,
			stats.task_count or 0,
			context.vault_path and (", " .. context.vault_path) or ""
		)
		vim.notify(message, vim.log.levels.INFO)
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksRunBlock", function(command)
		M.run_query_at_cursor({
			pinned = command.bang,
		})
	end, {
		bang = true,
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksPreviewToggle", function()
		require("obsidian-tasks.preview").toggle()
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksPreviewRefresh", function()
		require("obsidian-tasks.preview").refresh_buffer()
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksToggle", function()
		require("obsidian-tasks").toggle_task_at_cursor()
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksChangeStatus", function(command)
		require("obsidian-tasks").change_task_status_at_cursor(command.args)
	end, {
		nargs = "+",
		force = true,
		complete = function()
			return require("obsidian-tasks.status").complete_statuses()
		end,
	})

	vim.api.nvim_create_user_command("ObsidianTasksPostpone", function(command)
		require("obsidian-tasks").postpone_task_at_cursor(command.args)
	end, {
		nargs = "?",
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksEdit", function()
		require("obsidian-tasks").edit_current_task()
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksCreate", function(command)
		require("obsidian-tasks").create_task({
			file_path = command.args ~= "" and command.args or nil,
		})
	end, {
		nargs = "?",
		force = true,
		complete = "file",
	})

	vim.api.nvim_create_user_command("ObsidianTasksComplete", function()
		require("obsidian-tasks").complete_at_cursor()
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksAddDependency", function()
		require("obsidian-tasks").add_dependency_at_cursor()
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksPickDate", function(command)
		require("obsidian-tasks").pick_date_at_cursor({
			field = command.args ~= "" and command.args or "due",
			calendar = command.bang,
		})
	end, {
		bang = true,
		nargs = "?",
		force = true,
		complete = function()
			return { "due", "scheduled", "start", "created", "done", "cancelled" }
		end,
	})

	vim.api.nvim_create_user_command("ObsidianTasksAddQueryFileDefaults", function()
		require("obsidian-tasks").add_query_file_defaults_properties()
	end, {
		force = true,
	})

	vim.api.nvim_create_user_command("ObsidianTasksAddQueryFileDefaultsProperties", function()
		require("obsidian-tasks").add_query_file_defaults_properties()
	end, {
		force = true,
	})

	vim.keymap.set({ "i", "n" }, "<Plug>(ObsidianTasksComplete)", function()
		require("obsidian-tasks").complete_at_cursor()
	end, {
		noremap = true,
		silent = true,
		desc = "Complete Obsidian task field",
	})

	vim.keymap.set("n", "<Plug>(ObsidianTasksAddDependency)", function()
		require("obsidian-tasks").add_dependency_at_cursor()
	end, {
		noremap = true,
		silent = true,
		desc = "Add Obsidian task dependency",
	})

	vim.keymap.set("n", "<Plug>(ObsidianTasksPickDate)", function()
		require("obsidian-tasks").pick_date_at_cursor()
	end, {
		noremap = true,
		silent = true,
		desc = "Pick Obsidian task date",
	})

	require("obsidian-tasks.status").setup_status_commands()
end

return M
