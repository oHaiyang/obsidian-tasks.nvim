local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function read_lines(path)
	if not path or path == "" then
		return nil
	end
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

function M.lines(lines)
	lines = lines or {}
	if trim(lines[1]) ~= "---" then
		return {}
	end
	local result = {}
	for index = 2, #lines do
		local line = lines[index]
		local trimmed = trim(line)
		if trimmed == "---" or trimmed == "..." then
			return result
		end
		table.insert(result, line)
	end
	return {}
end

local function unquote(value)
	local quoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
	if quoted ~= nil then
		return quoted
	end
	return value
end

local function parse_inline_array(value)
	local inner = value:match("^%[(.*)%]$")
	if inner == nil then
		return nil
	end
	local items = {}
	for item in (inner .. ","):gmatch("(.-),") do
		item = trim(item)
		if item ~= "" then
			table.insert(items, unquote(item))
		end
	end
	return items
end

function M.parse_scalar(value)
	value = trim(value)
	if value == "" then
		return nil
	end

	local array = parse_inline_array(value)
	if array then
		return array
	end

	value = unquote(value)
	local lower = value:lower()
	if lower == "true" then
		return true
	elseif lower == "false" then
		return false
	elseif lower == "null" or lower == "~" then
		return nil
	end

	local number = tonumber(value)
	if number ~= nil then
		return number
	end
	return value
end

local function is_top_level_property(line)
	return line:match("^[%w_%-]+:%s*") ~= nil
end

local function block_value(lines, start_index)
	local collected = {}
	local index = start_index + 1

	while index <= #lines do
		local line = lines[index]
		if is_top_level_property(line) then
			break
		end
		table.insert(collected, line)
		index = index + 1
	end

	local has_content = false
	for _, line in ipairs(collected) do
		if trim(line) ~= "" then
			has_content = true
			break
		end
	end
	if not has_content then
		return nil, index
	end

	local list = {}
	for _, line in ipairs(collected) do
		local item = line:match("^%s*%-%s+(.+)$")
		if item then
			table.insert(list, M.parse_scalar(item))
		elseif trim(line) ~= "" then
			list = nil
			break
		end
	end
	if list and #list > 0 then
		return list, index
	end

	local min_indent
	for _, line in ipairs(collected) do
		if trim(line) ~= "" then
			local indent = #(line:match("^%s*") or "")
			min_indent = min_indent and math.min(min_indent, indent) or indent
		end
	end
	if min_indent and min_indent > 0 then
		for item_index, line in ipairs(collected) do
			if #line >= min_indent then
				collected[item_index] = line:sub(min_indent + 1)
			end
		end
	end
	return table.concat(collected, "\n"), index
end

function M.parse(lines)
	lines = M.lines(lines)
	local props = {}
	local index = 1

	while index <= #lines do
		local key, value = lines[index]:match("^([%w_%-]+):%s*(.-)%s*$")
		if key then
			if value == "" or value:match("^[|>]") then
				props[key], index = block_value(lines, index)
			else
				props[key] = M.parse_scalar(value)
				index = index + 1
			end
		else
			index = index + 1
		end
	end

	return props
end

function M.parse_file(path)
	return M.parse(read_lines(path) or {})
end

local function as_list(value)
	if type(value) == "table" then
		return value
	end
	if type(value) == "string" and value ~= "" then
		return { value }
	end
	return {}
end

function M.file_fields(props)
	props = props or {}
	return {
		frontmatter = props,
		properties = props,
		tags = as_list(props.tags),
		aliases = as_list(props.aliases or props.alias),
		cssclasses = as_list(props.cssclasses or props.cssclass),
		classes = as_list(props.cssclasses or props.cssclass),
	}
end

return M
