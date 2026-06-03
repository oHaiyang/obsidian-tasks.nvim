local M = {}

-- Re-export functions from other modules
---@param config? ObsidianTasksConfig
---@return ObsidianTasks
function M.setup(config)
	-- Load modules
	local core = require("obsidian-tasks.core")

	-- Initialize with config
	config = config or {}
	local vault_path = config.vault_path

	-- Default display options
	config.display = config.display or {}
	config.display.hierarchical_headings = config.display.hierarchical_headings or false
	config.global_filter = config.global_filter or config.globalFilter or ""
	config.global_query = config.global_query or config.globalQuery or ""
	config.queries = config.queries or {}
	config.default_query = config.default_query or config.defaultQuery
	config.presets = config.presets or config.query_presets or config.queryPresets or {}
	config.task_format = config.task_format or config.taskFormat or "tasks"
	if type(config.cache) ~= "table" then
		config.cache = {
			enabled = config.cache == true,
		}
	end
	if config.cache_enabled ~= nil then
		config.cache.enabled = config.cache_enabled
	end
	if config.cacheEnabled ~= nil then
		config.cache.enabled = config.cacheEnabled
	end
	if config.cache.auto_update_on_write == nil then
		config.cache.auto_update_on_write = config.cache.autoUpdateOnWrite
	end
	if config.cache.auto_update_on_write == nil then
		config.cache.auto_update_on_write = true
	end
	config.cache.debounce_ms = config.cache.debounce_ms or config.cache.debounceMs or 0
	config.enable_lua_filters = config.enable_lua_filters or config.enableLuaFilters or false
	config.inbox_file = config.inbox_file or config.inboxFile
	config.status_settings = config.status_settings or config.statusSettings or config.statuses
	config.set_done_date = config.set_done_date or config.setDoneDate or false
	config.set_cancelled_date = config.set_cancelled_date or config.setCancelledDate or false
	config.set_created_date = config.set_created_date or config.setCreatedDate or false
	config.recurrence_on_next_line = config.recurrence_on_next_line or config.recurrenceOnNextLine or false
	config.remove_scheduled_date_on_recurrence = config.remove_scheduled_date_on_recurrence
		or config.removeScheduledDateOnRecurrence
		or false
	if config.auto_suggest_in_editor == nil then
		config.auto_suggest_in_editor = config.autoSuggestInEditor
	end
	if config.auto_suggest_in_editor == nil then
		config.auto_suggest_in_editor = true
	end
	config.auto_suggest_min_chars = config.auto_suggest_min_chars or config.autoSuggestMinChars or 0
	config.auto_suggest_max_items = config.auto_suggest_max_items or config.autoSuggestMaxItems or 20
	if type(config.completion) ~= "table" then
		config.completion = {}
	end

	-- Store config for other modules to access
	M.config = config
	require("obsidian-tasks.panel").setup_commands()
	require("obsidian-tasks.cache").setup(config)
	local cmp_config = config.completion.cmp or config.completion.nvim_cmp or config.completion.nvimCmp
	if cmp_config then
		local ok_cmp_source, cmp_source = pcall(require, "obsidian-tasks.completion.cmp")
		if ok_cmp_source then
			pcall(cmp_source.register, type(cmp_config) == "table" and cmp_config or {})
		end
	end
	local native_config = config.completion.native or config.completion.native_completion or config.completion.nativeCompletion
	if native_config then
		local ok_native, native = pcall(require, "obsidian-tasks.completion.native")
		if ok_native then
			pcall(native.setup, native_config)
		end
	end

	-- Register tree-sitter parser when available. Command registration should
	-- not depend on tree-sitter support in the user's Neovim build.
	if vim.treesitter and vim.treesitter.language and vim.treesitter.language.register then
		pcall(vim.treesitter.language.register, "markdown", "obstasks")
	end

	return M
end

-- Re-export main API functions
---@param opts? ObsidianTaskFinderOptions
function M.find_tasks(opts)
	opts = opts or {}

	-- Apply global config options if not specified in the call
	if M.config and M.config.display then
		if opts.hierarchical_headings == nil then
			opts.hierarchical_headings = M.config.display.hierarchical_headings
		end
	end
	if M.config then
		if opts.vault_path == nil then
			opts.vault_path = M.config.vault_path
		end
		if opts.global_filter == nil and opts.globalFilter == nil then
			opts.global_filter = M.config.global_filter
		end
	end

	return require("obsidian-tasks.finder").find_tasks(opts)
end

---@return boolean success
function M.save_current_tasks()
	return require("obsidian-tasks.core").save_current_tasks()
end

---@return boolean success
function M.toggle_task_at_cursor()
	return require("obsidian-tasks.core").toggle_task_at_cursor()
end

function M.change_task_status_at_cursor(status)
	return require("obsidian-tasks.core").change_task_status_at_cursor(status)
end

function M.postpone_task_at_cursor(expr)
	return require("obsidian-tasks.core").postpone_task_at_cursor(expr)
end

function M.edit_current_task()
	return require("obsidian-tasks.edit").edit_current_task()
end

function M.create_task(opts)
	return require("obsidian-tasks.edit").create_task(opts)
end

function M.complete_at_cursor(opts)
	return require("obsidian-tasks.completion").trigger_markdown_complete(opts)
end

function M.add_dependency_at_cursor(opts)
	return require("obsidian-tasks.dependency_editor").add_dependency_at_cursor(opts)
end

function M.pick_date_at_cursor(opts)
	return require("obsidian-tasks.date_picker").pick_at_cursor(opts)
end

function M.add_query_file_defaults_properties(opts)
	opts = opts or {}
	return require("obsidian-tasks.query_file_defaults").add_all_properties_to_buffer(opts.buf or opts.buffer or 0)
end

function M.refresh_cache(opts)
	opts = opts or {}
	if opts.vault_path == nil then
		opts.vault_path = M.config and M.config.vault_path
	end
	if opts.global_filter == nil and opts.globalFilter == nil then
		opts.global_filter = M.config and M.config.global_filter
	end
	return require("obsidian-tasks.cache").refresh(opts)
end

function M.clear_cache()
	return require("obsidian-tasks.cache").clear()
end

function M.cache_stats()
	return require("obsidian-tasks.cache").stats()
end

function M.setup_cmp(opts)
	return require("obsidian-tasks.completion.cmp").register(opts)
end

function M.open(opts)
	return require("obsidian-tasks.panel").open(opts)
end

function M.open_query(name, opts)
	return require("obsidian-tasks.panel").open_query(name, opts)
end

function M.run_query(query, opts)
	return require("obsidian-tasks.panel").run_query(query, opts)
end

function M.run_query_at_cursor(opts)
	return require("obsidian-tasks.panel").run_query_at_cursor(opts)
end

function M.refresh_queries(opts)
	return require("obsidian-tasks.panel").refresh_queries(opts)
end

function M.preview_toggle()
	return require("obsidian-tasks.preview").toggle()
end

function M.preview_refresh()
	return require("obsidian-tasks.preview").refresh_buffer()
end

return M
