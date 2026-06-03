local M = {}

local date = require("obsidian-tasks.date")
local scanner = require("obsidian-tasks.scanner")

local AUGROUP = "ObsidianTasksCache"

M.state = {
	status = "cold",
	context = nil,
	files = {},
	tasks = {},
	last_refresh = nil,
	last_update = nil,
}
M.pending_updates = {}

local function get_config()
	local ok, plugin = pcall(require, "obsidian-tasks")
	if ok and plugin then
		return plugin.config or {}
	end
	return {}
end

local function realpath(path)
	if not path or path == "" then
		return path
	end
	local uv = vim.uv or vim.loop
	return (uv and uv.fs_realpath(path)) or path
end

local function normalize_vault_path(path)
	path = realpath(path)
	if type(path) == "string" then
		return path:gsub("/+$", "")
	end
	return path
end

local function markdown_files(vault_path)
	local pattern = vim.fs and vim.fs.joinpath and vim.fs.joinpath(vault_path, "**", "*.md")
		or (vault_path:gsub("/$", "") .. "/**/*.md")
	local files = vim.fn.glob(pattern, false, true)
	table.sort(files)
	return files
end

local function cache_config(config)
	config = config or get_config()
	local cache = config.cache
	if type(cache) == "table" then
		return cache
	end
	return {
		enabled = cache == true,
	}
end

local function cache_auto_update_enabled(config)
	local cache = cache_config(config)
	if cache.enabled ~= true then
		return false
	end
	if cache.auto_update_on_write ~= nil then
		return cache.auto_update_on_write ~= false
	end
	if cache.autoUpdateOnWrite ~= nil then
		return cache.autoUpdateOnWrite ~= false
	end
	return true
end

local function cache_debounce_ms(config)
	local cache = cache_config(config)
	return tonumber(cache.debounce_ms or cache.debounceMs or 0) or 0
end

function M.is_enabled(opts)
	opts = opts or {}
	local explicit = opts.use_cache
	if explicit == nil then
		explicit = opts.useCache
	end
	if explicit ~= nil then
		return explicit == true
	end

	local config = opts.config or get_config()
	local cache = cache_config(config)
	return cache.enabled == true
end

local function context(opts)
	opts = opts or {}
	local config = opts.config or get_config()
	return {
		vault_path = normalize_vault_path(opts.vault_path or config.vault_path),
		global_filter = opts.global_filter or opts.globalFilter or config.global_filter or "",
		today = opts.today or config.today or date.today(),
		task_format = config.task_format or config.taskFormat or "tasks",
	}
end

local function same_context(left, right)
	if not left or not right then
		return false
	end
	return left.vault_path == right.vault_path
		and left.global_filter == right.global_filter
		and left.today == right.today
		and left.task_format == right.task_format
end

function M.is_path_in_vault(path, vault_path)
	local normalized_path = realpath(path)
	local normalized_vault = normalize_vault_path(vault_path)
	if not normalized_path or normalized_path == "" or not normalized_vault or normalized_vault == "" then
		return false
	end
	return normalized_path == normalized_vault or normalized_path:sub(1, #normalized_vault + 1) == normalized_vault .. "/"
end

local function copy_task_list(tasks)
	local copied = {}
	for _, task in ipairs(tasks or {}) do
		table.insert(copied, task)
	end
	return copied
end

local function scan_file(path, ctx)
	local normalized = realpath(path) or path
	local uv = vim.uv or vim.loop
	local stat = uv and uv.fs_stat(normalized) or nil
	return {
		path = normalized,
		mtime = stat and stat.mtime and stat.mtime.sec or nil,
		size = stat and stat.size or nil,
		tasks = scanner.scan_file(normalized, {
			global_filter = ctx.global_filter,
			today = ctx.today,
		}),
	}
end

local function rebuild_tasks()
	local tasks = {}
	local paths = {}
	for path in pairs(M.state.files or {}) do
		table.insert(paths, path)
	end
	table.sort(paths)
	for _, path in ipairs(paths) do
		for _, task in ipairs(M.state.files[path].tasks or {}) do
			table.insert(tasks, task)
		end
	end
	M.state.tasks = tasks
end

local function refresh_current_result(opts)
	opts = opts or {}
	local ok, display = pcall(require, "obsidian-tasks.display")
	if not ok then
		return false
	end
	local buf = vim.api.nvim_get_current_buf()
	if not display.buffer_finder_opts or not display.buffer_finder_opts[buf] then
		return false
	end
	return display.refresh_tasks_view({
		buffer = buf,
		notify = opts.notify,
	})
end

function M.clear()
	M.state = {
		status = "cold",
		context = nil,
		files = {},
		tasks = {},
		last_refresh = nil,
		last_update = nil,
	}
end

function M.refresh(opts)
	opts = opts or {}
	local ctx = context(opts)
	if not ctx.vault_path or ctx.vault_path == "" then
		M.clear()
		return {}
	end

	local files = {}
	for _, path in ipairs(markdown_files(ctx.vault_path)) do
		local normalized = realpath(path) or path
		files[normalized] = scan_file(normalized, ctx)
	end

	M.state = {
		status = "warm",
		context = ctx,
		files = files,
		tasks = {},
		last_refresh = os.time(),
		last_update = nil,
	}
	rebuild_tasks()
	if opts.refresh_results or opts.refreshResults then
		refresh_current_result({
			notify = opts.notify_results or opts.notifyResults or false,
		})
	end
	return copy_task_list(M.state.tasks)
end

local function ensure_warm(opts)
	local ctx = context(opts)
	if M.state.status ~= "warm" or not same_context(M.state.context, ctx) then
		M.refresh(opts)
	end
end

function M.tasks(opts)
	opts = opts or {}
	if not M.is_enabled(opts) then
		return scanner.scan_vault(opts)
	end

	ensure_warm(opts)
	return copy_task_list(M.state.tasks)
end

function M.update_file(path, opts)
	opts = opts or {}
	local ctx = context(opts)
	if M.state.status ~= "warm" or not same_context(M.state.context, ctx) then
		local refresh_if_cold = opts.refresh_if_cold
		if refresh_if_cold == nil then
			refresh_if_cold = opts.refreshIfCold
		end
		if refresh_if_cold == false then
			return {}
		end
		M.refresh(opts)
	end
	if not path or path == "" then
		return {}
	end

	local normalized = realpath(path) or path
	local uv = vim.uv or vim.loop
	if uv and not uv.fs_stat(normalized) then
		M.state.files[normalized] = nil
		rebuild_tasks()
		M.state.last_update = os.time()
		return {}
	end
	if normalized:sub(-3) ~= ".md" then
		M.state.files[normalized] = nil
		rebuild_tasks()
		M.state.last_update = os.time()
		return {}
	end

	M.state.files[normalized] = scan_file(normalized, M.state.context or ctx)
	rebuild_tasks()
	M.state.last_update = os.time()
	return copy_task_list(M.state.files[normalized].tasks)
end

function M.remove_file(path)
	if not path or path == "" then
		return
	end
	M.state.files[realpath(path) or path] = nil
	rebuild_tasks()
	M.state.last_update = os.time()
end

function M.on_file_changed(path, opts)
	opts = opts or {}
	local config = opts.config or get_config()
	if not M.is_enabled({ config = config }) then
		return false
	end

	local ctx = context({ config = config })
	if not path or path == "" or path:sub(-3) ~= ".md" or not M.is_path_in_vault(path, ctx.vault_path) then
		return false
	end

	M.update_file(path, {
		config = config,
		refresh_if_cold = false,
	})
	return true
end

function M.on_buf_write(path, opts)
	opts = opts or {}
	local config = opts.config or get_config()
	if not cache_auto_update_enabled(config) then
		return false
	end

	local ctx = context({ config = config })
	if not path or path == "" or path:sub(-3) ~= ".md" or not M.is_path_in_vault(path, ctx.vault_path) then
		return false
	end

	local normalized = realpath(path) or path
	local debounce_ms = cache_debounce_ms(config)
	if debounce_ms <= 0 then
		return M.on_file_changed(normalized, { config = config })
	end

	local token = (M.pending_updates[normalized] or 0) + 1
	M.pending_updates[normalized] = token
	vim.defer_fn(function()
		if M.pending_updates[normalized] ~= token then
			return
		end
		M.pending_updates[normalized] = nil
		M.on_file_changed(normalized, { config = config })
	end, debounce_ms)
	return true
end

function M.setup(config)
	config = config or get_config()
	local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
	if not cache_auto_update_enabled(config) then
		return
	end

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = "*.md",
		callback = function(args)
			M.on_buf_write(args.file, { config = config })
		end,
	})
end

function M.stats()
	local file_count = 0
	for _ in pairs(M.state.files or {}) do
		file_count = file_count + 1
	end
	return {
		status = M.state.status,
		context = M.state.context,
		file_count = file_count,
		task_count = #(M.state.tasks or {}),
		last_refresh = M.state.last_refresh,
		last_update = M.state.last_update,
	}
end

return M
