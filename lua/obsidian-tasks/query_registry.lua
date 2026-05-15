local M = {}

M.block_cache = {
	vault_path = nil,
	sources = nil,
}
M.recent_sources = {}

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function normalize_config_source(id, value)
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
			end_line = value.end_line,
		}
	end
	return nil
end

local function config_sources()
	local queries = get_config().queries or {}
	local sources = {}

	if #queries > 0 then
		for index, item in ipairs(queries) do
			local source = normalize_config_source(item.id or item.name or tostring(index), item)
			if source and source.query ~= "" then
				table.insert(sources, source)
			end
		end
	else
		for id, value in pairs(queries) do
			local source = normalize_config_source(id, value)
			if source and source.query ~= "" then
				table.insert(sources, source)
			end
		end
	end

	return sources
end

local function source_path_label(source)
	if source.source_path and source.source_line then
		local filename = source.source_path:match("([^/]+)$") or source.source_path
		return string.format("%s#L%d", filename, source.source_line)
	end
	return nil
end

local function decorate(source)
	source.qualified_id = source.source_type .. ":" .. source.id
	if source.source_type == "block" and source.source_path and source.source_line then
		source.qualified_id = string.format("block:%s:%s:%d", source.id, source.source_path, source.source_line)
	end
	source.source_label = source_path_label(source)
	return source
end

function M.refresh(opts)
	opts = opts or {}
	local config = get_config()
	local vault_path = opts.vault_path or config.vault_path
	local sources = {}

	if vault_path and vault_path ~= "" then
		sources = require("obsidian-tasks.query_block").scan_vault({
			vault_path = vault_path,
		})
	end

	M.block_cache = {
		vault_path = vault_path,
		sources = sources,
	}

	return sources
end

local function block_sources(opts)
	opts = opts or {}
	local config = get_config()
	local vault_path = opts.vault_path or config.vault_path

	if
		opts.refresh
		or not M.block_cache.sources
		or M.block_cache.vault_path ~= vault_path
	then
		M.refresh({
			vault_path = vault_path,
		})
	end

	return M.block_cache.sources or {}
end

function M.add_recent(source)
	if not source or not source.query or source.query == "" then
		return
	end

	local recent = {
		id = source.id or "manual",
		name = source.name or "manual",
		query = source.query,
		source_type = "recent",
	}

	table.insert(M.recent_sources, 1, recent)
	if #M.recent_sources > 5 then
		table.remove(M.recent_sources)
	end
end

function M.get_sources(opts)
	opts = opts or {}
	local sources = {}

	for _, source in ipairs(config_sources()) do
		table.insert(sources, decorate(source))
	end

	for _, source in ipairs(block_sources(opts)) do
		table.insert(sources, decorate(source))
	end

	for _, source in ipairs(M.recent_sources) do
		table.insert(sources, decorate(source))
	end

	table.sort(sources, function(left, right)
		if left.source_type ~= right.source_type then
			local order = {
				config = 1,
				block = 2,
				recent = 3,
			}
			return (order[left.source_type] or 99) < (order[right.source_type] or 99)
		end
		return tostring(left.name) < tostring(right.name)
	end)

	return sources
end

function M.find_source(name, opts)
	local sources = M.get_sources(opts)
	if #sources == 0 then
		return nil, sources
	end

	if name and name ~= "" then
		for _, source in ipairs(sources) do
			if source.qualified_id == name or source.id == name or source.name == name then
				return source, sources
			end
		end
		return nil, sources
	end

	return nil, sources
end

function M.complete_names()
	local names = {}
	for _, source in ipairs(M.get_sources()) do
		table.insert(names, source.id)
		if source.qualified_id and source.qualified_id ~= source.id then
			table.insert(names, source.qualified_id)
		end
	end
	return names
end

function M.format_source(source)
	local label = source.name or source.id
	local kind = source.source_type or "query"
	if source.source_label then
		return string.format("%-28s %-8s %s", label, kind, source.source_label)
	end
	return string.format("%-28s %s", label, kind)
end

return M
