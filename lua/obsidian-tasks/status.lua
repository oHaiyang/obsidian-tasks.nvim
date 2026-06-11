local M = {}

local task_model = require("obsidian-tasks.task")

M.DEFAULT_STATUSES = {
	{ symbol = " ", name = "Todo", type = "TODO", next_symbol = "x" },
	{ symbol = "x", name = "Done", type = "DONE", next_symbol = " " },
	{ symbol = "/", name = "In Progress", type = "IN_PROGRESS", next_symbol = "x" },
	{ symbol = "-", name = "Cancelled", type = "CANCELLED", next_symbol = " " },
}

local COMPLETE_TYPES = {
	DONE = true,
	CANCELLED = true,
	NON_TASK = true,
}

local vault_status_settings_cache = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function join_path(...)
	if vim.fs and vim.fs.joinpath then
		return vim.fs.joinpath(...)
	end

	local parts = { ... }
	local path = tostring(parts[1] or "")
	for index = 2, #parts do
		local part = tostring(parts[index] or "")
		if part ~= "" then
			path = path:gsub("/+$", "") .. "/" .. part:gsub("^/+", "")
		end
	end
	return path
end

local function normalize_path(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end

	local expanded = vim.fn.expand(path)
	local absolute = vim.fn.fnamemodify(expanded, ":p")
	return absolute:gsub("/+$", "")
end

local function obsidian_tasks_data_path(vault_path)
	vault_path = normalize_path(vault_path)
	if not vault_path then
		return nil
	end
	return join_path(vault_path, ".obsidian", "plugins", "obsidian-tasks-plugin", "data.json")
end

local function file_signature(path)
	local uv = vim.uv or vim.loop
	if uv and uv.fs_stat then
		local ok, stat = pcall(uv.fs_stat, path)
		if ok and stat then
			local mtime = stat.mtime or {}
			return table.concat({
				tostring(stat.size or 0),
				tostring(mtime.sec or 0),
				tostring(mtime.nsec or 0),
			}, ":")
		end
	end

	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	return table.concat({
		tostring(vim.fn.getfsize(path)),
		tostring(vim.fn.getftime(path)),
		"0",
	}, ":")
end

local function decode_json(content)
	if vim.json and vim.json.decode then
		local ok, decoded = pcall(vim.json.decode, content)
		if ok then
			return decoded
		end
	end

	local ok, decoded = pcall(vim.fn.json_decode, content)
	if ok then
		return decoded
	end
	return nil
end

local function read_json_file(path)
	if type(path) ~= "string" or vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end

	local decoded = decode_json(table.concat(lines, "\n"))
	if type(decoded) == "table" then
		return decoded
	end
	return nil
end

local function normalize_type(value)
	value = trim(value):upper():gsub("%s+", "_"):gsub("%-", "_")
	if value == "" then
		return "TODO"
	end
	return value
end

function M.normalize_symbol(value)
	value = tostring(value or "")
	local inner = value:match("^%[(.*)%]$")
	if inner ~= nil then
		value = inner
	end
	if value == "" then
		return " "
	end
	return value
end

function M.status_text(value)
	return task_model.status_text(M.normalize_symbol(value))
end

local function normalize_entry(entry)
	if type(entry) == "string" then
		entry = { symbol = entry }
	end
	if type(entry) ~= "table" then
		return nil
	end
	if entry[1] ~= nil or entry[2] ~= nil or entry[3] ~= nil or entry[4] ~= nil then
		entry = {
			symbol = entry[1],
			name = entry[2],
			nextStatusSymbol = entry[3],
			type = entry[4],
		}
	end

	local symbol = M.normalize_symbol(entry.symbol or entry.character or entry.char or entry.status_symbol or entry.statusSymbol)
	local next_symbol = entry.next_symbol or entry.nextSymbol or entry.next or entry.nextStatusSymbol
	if next_symbol ~= nil then
		next_symbol = M.normalize_symbol(next_symbol)
	end

	return {
		symbol = symbol,
		name = trim(entry.name or entry.label or symbol),
		type = normalize_type(entry.type or entry.status_type or entry.statusType),
		next_symbol = next_symbol,
		available_as_command = entry.available_as_command ~= false and entry.availableAsCommand ~= false,
	}
end

local function append_entries(target, source)
	if type(source) ~= "table" then
		return
	end
	for _, entry in ipairs(source) do
		table.insert(target, entry)
	end
end

local function status_settings_entries(settings)
	if type(settings) ~= "table" then
		return settings
	end

	local core = settings.coreStatuses or settings.core_statuses
	local custom = settings.customStatuses or settings.custom_statuses
	if core ~= nil or custom ~= nil then
		local entries = {}
		append_entries(entries, core)
		append_entries(entries, custom)
		return entries
	end

	return settings
end

local function configured_status_setting(config)
	if config.status_settings ~= nil then
		return config.status_settings
	end
	if config.statusSettings ~= nil then
		return config.statusSettings
	end
	if config.statuses ~= nil then
		return config.statuses
	end
	return nil
end

local function vault_status_settings(config)
	local path = obsidian_tasks_data_path(config.vault_path or config.vaultPath)
	if not path then
		return nil
	end

	local signature = file_signature(path)
	if not signature then
		vault_status_settings_cache[path] = nil
		return nil
	end

	local cached = vault_status_settings_cache[path]
	if cached and cached.signature == signature then
		return cached.settings
	end

	local data = read_json_file(path)
	local settings = type(data) == "table" and (data.statusSettings or data.status_settings) or nil
	vault_status_settings_cache[path] = {
		signature = signature,
		settings = settings,
	}
	return settings
end

local function configured_statuses(config)
	config = config or {}
	local explicit = configured_status_setting(config)
	if explicit ~= nil then
		return status_settings_entries(explicit)
	end
	return status_settings_entries(vault_status_settings(config))
end

local function is_list(value)
	return (vim.islist or vim.tbl_islist)(value)
end

function M.registry(config)
	local entries = {}
	local by_symbol = {}
	local source = configured_statuses(config)

	if type(source) == "table" then
		if is_list(source) then
			for _, value in ipairs(source) do
				local normalized = normalize_entry(value)
				if normalized and not by_symbol[normalized.symbol] then
					table.insert(entries, normalized)
					by_symbol[normalized.symbol] = normalized
				end
			end
		else
			for key, value in pairs(source) do
				local entry = value
				if type(key) == "string" and type(value) == "table" and value.symbol == nil then
					entry = vim.tbl_extend("force", { symbol = key }, value)
				end
				local normalized = normalize_entry(entry)
				if normalized and not by_symbol[normalized.symbol] then
					table.insert(entries, normalized)
					by_symbol[normalized.symbol] = normalized
				end
			end
		end
	end

	for _, entry in ipairs(M.DEFAULT_STATUSES) do
		local normalized = normalize_entry(entry)
		if normalized and not by_symbol[normalized.symbol] then
			table.insert(entries, normalized)
			by_symbol[normalized.symbol] = normalized
		end
	end

	for _, entry in ipairs(entries) do
		if entry.next_symbol == nil then
			entry.next_symbol = entry.type == "DONE" and " " or "x"
		end
	end

	return entries, by_symbol
end

local function get_config()
	local ok, plugin = pcall(require, "obsidian-tasks")
	if ok and plugin then
		return plugin.config or {}
	end
	return {}
end

function M.get(symbol, config)
	local _, by_symbol = M.registry(config or get_config())
	return by_symbol[M.normalize_symbol(symbol)] or {
		symbol = M.normalize_symbol(symbol),
		name = "Unknown",
		type = "TODO",
		next_symbol = "x",
		available_as_command = true,
	}
end

function M.type(symbol, config)
	return M.get(symbol, config).type
end

function M.is_complete_symbol(symbol, config)
	return COMPLETE_TYPES[M.type(symbol, config)] == true
end

function M.is_incomplete_symbol(symbol, config)
	return not M.is_complete_symbol(symbol, config)
end

function M.next_symbol(symbol, config)
	return M.get(symbol, config).next_symbol or " "
end

function M.with_status(task, symbol)
	local updated = {}
	for key, value in pairs(task or {}) do
		updated[key] = value
	end
	updated.status_symbol = M.normalize_symbol(symbol)
	updated.status = M.status_text(updated.status_symbol)
	return updated
end

function M.resolve_symbol(value, config)
	value = trim(value)
	if value == "" then
		return nil
	end

	local normalized = M.normalize_symbol(value)
	local entries, by_symbol = M.registry(config or get_config())
	if by_symbol[normalized] then
		return normalized
	end

	local lookup = value:lower():gsub("[%s%-]+", "_")
	for _, entry in ipairs(entries) do
		if entry.name:lower() == value:lower() or entry.type:lower() == lookup then
			return entry.symbol
		end
	end

	return nil
end

function M.complete_statuses(config)
	local items = {}
	for _, entry in ipairs(M.registry(config or get_config())) do
		if entry.available_as_command then
			table.insert(items, entry.name)
			if entry.type ~= "" then
				table.insert(items, entry.type)
			end
			if entry.symbol ~= " " then
				table.insert(items, entry.symbol)
			end
		end
	end
	return items
end

local function command_suffix(entry)
	local base = entry.name ~= "" and entry.name or entry.type or entry.symbol
	base = base:gsub("[^%w]+", " ")
	local suffix = ""
	for part in base:gmatch("%w+") do
		suffix = suffix .. part:sub(1, 1):upper() .. part:sub(2):lower()
	end
	return suffix ~= "" and suffix or nil
end

function M.setup_status_commands(config)
	config = config or get_config()
	for _, entry in ipairs(M.registry(config)) do
		if entry.available_as_command and entry.type ~= "NON_TASK" then
			local suffix = command_suffix(entry)
			if suffix then
				vim.api.nvim_create_user_command("ObsidianTasksStatus" .. suffix, function()
					require("obsidian-tasks").change_task_status_at_cursor(entry.symbol)
				end, {
					force = true,
					desc = "Change task status to " .. entry.name,
				})
			end
		end
	end
end

return M
