local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function basename(path)
	return (path or ""):match("([^/]+)$") or path or ""
end

local function slug(value)
	value = trim(value)
	value = value:gsub("[^%w_%-]+", "-")
	value = value:gsub("%-+", "-")
	value = value:gsub("^%-", ""):gsub("%-$", "")
	if value == "" then
		return "query"
	end
	return value:lower()
end

local function read_lines(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()
	return lines
end

local function markdown_files(vault_path)
	local pattern = vim.fs and vim.fs.joinpath and vim.fs.joinpath(vault_path, "**", "*.md")
		or (vault_path:gsub("/$", "") .. "/**/*.md")
	return vim.fn.glob(pattern, false, true)
end

local function split_blockquote(line)
	line = line or ""
	local prefix = ""
	local rest = line
	while true do
		local quoted, after = rest:match("^(%s*>%s*)(.*)$")
		if not quoted then
			break
		end
		prefix = prefix .. quoted
		rest = after
	end
	if prefix ~= "" then
		return prefix, rest
	end
	return nil, line
end

local function opening_fence(line)
	local quote_prefix
	quote_prefix, line = split_blockquote(line)
	local marker, info = line:match("^%s*(```+)%s*(.-)%s*$")
	if marker then
		return marker:sub(1, 1), #marker, trim(info or ""), quote_prefix
	end

	marker, info = line:match("^%s*(~~~+)%s*(.-)%s*$")
	if marker then
		return marker:sub(1, 1), #marker, trim(info or ""), quote_prefix
	end

	return nil
end

local function closing_fence(line, marker_char, marker_len, quote_prefix)
	if quote_prefix then
		local line_quote
		line_quote, line = split_blockquote(line)
		if not line_quote then
			return false
		end
	end
	local marker
	if marker_char == "`" then
		marker = line:match("^%s*(```+)%s*$")
	elseif marker_char == "~" then
		marker = line:match("^%s*(~~~+)%s*$")
	end
	return marker and #marker >= marker_len
end

local function is_tasks_info(info)
	local token = (info or ""):match("^(%S+)") or ""
	return token:lower() == "tasks"
end

local function metadata(lines)
	local result = {}
	for _, line in ipairs(lines) do
		local key, value = line:match("^%s*#%s*([%w_%-]+)%s*:%s*(.-)%s*$")
		if key and value then
			result[key:lower()] = trim(value)
		end
	end
	return result
end

local function source_from_block(path, start_line, end_line, block_lines, quote_prefix)
	local meta = metadata(block_lines)
	local name = meta.name
	local id = meta.id
	local unnamed = false

	if not name or name == "" then
		name = string.format("Unnamed query (%s#L%d)", basename(path), start_line)
		unnamed = true
	end

	if not id or id == "" then
		id = unnamed and slug(path .. "-" .. start_line) or slug(name)
	end

	return {
		id = id,
		name = name,
		query = table.concat(block_lines, "\n"),
		source_type = "block",
		source_path = path,
		source_line = start_line,
		end_line = end_line,
		unnamed = unnamed,
		quote_prefix = quote_prefix,
	}
end

function M.scan_lines(lines, path)
	local sources = {}
	local line_count = #lines
	local index = 1

	while index <= line_count do
		local marker_char, marker_len, info, quote_prefix = opening_fence(lines[index])
		if marker_char then
			local start_line = index
			local block_lines = {}
			index = index + 1

			while index <= line_count and not closing_fence(lines[index], marker_char, marker_len, quote_prefix) do
				if is_tasks_info(info) then
					local block_line = lines[index]
					if quote_prefix then
						local line_quote, unquoted = split_blockquote(block_line)
						if line_quote then
							block_line = unquoted
						end
					end
					table.insert(block_lines, block_line)
				end
				index = index + 1
			end

			local end_line = index <= line_count and index or line_count
			if is_tasks_info(info) then
				table.insert(sources, source_from_block(path, start_line, end_line, block_lines, quote_prefix))
			end
		end

		index = index + 1
	end

	return sources
end

function M.scan_file(path)
	local lines = read_lines(path)
	if not lines then
		return {}
	end
	return M.scan_lines(lines, path)
end

function M.scan_buffer(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return M.scan_lines(lines, path)
end

function M.find_at_cursor(buf, row)
	buf = buf or vim.api.nvim_get_current_buf()
	row = row or vim.api.nvim_win_get_cursor(0)[1]

	for _, source in ipairs(M.scan_buffer(buf)) do
		if row >= source.source_line and row <= source.end_line then
			return source
		end
	end

	return nil
end

function M.scan_vault(opts)
	opts = opts or {}
	local vault_path = opts.vault_path
	if not vault_path or vault_path == "" then
		return {}
	end

	local sources = {}
	for _, path in ipairs(markdown_files(vault_path)) do
		if path:sub(-3) == ".md" then
			for _, source in ipairs(M.scan_file(path)) do
				table.insert(sources, source)
			end
		end
	end

	return sources
end

return M
