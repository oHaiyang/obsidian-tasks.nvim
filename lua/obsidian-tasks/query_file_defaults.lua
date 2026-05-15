local M = {}

local PROPERTIES = {
	{ name = "TQ_show_toolbar", handler = "show_hide", display = "toolbar" },
	{ name = "TQ_explain", handler = "instruction", true_value = "explain", false_value = "" },
	{ name = "TQ_short_mode", handler = "instruction", true_value = "short mode", false_value = "full mode" },
	{ name = "TQ_show_tree", handler = "show_hide", display = "tree" },
	{ name = "TQ_show_tags", handler = "show_hide", display = "tags" },
	{ name = "TQ_show_id", handler = "show_hide", display = "id" },
	{ name = "TQ_show_depends_on", handler = "show_hide", display = "depends on" },
	{ name = "TQ_show_priority", handler = "show_hide", display = "priority" },
	{ name = "TQ_show_recurrence_rule", handler = "show_hide", display = "recurrence rule" },
	{ name = "TQ_show_on_completion", handler = "show_hide", display = "on completion" },
	{ name = "TQ_show_created_date", handler = "show_hide", display = "created date" },
	{ name = "TQ_show_start_date", handler = "show_hide", display = "start date" },
	{ name = "TQ_show_scheduled_date", handler = "show_hide", display = "scheduled date" },
	{ name = "TQ_show_due_date", handler = "show_hide", display = "due date" },
	{ name = "TQ_show_cancelled_date", handler = "show_hide", display = "cancelled date" },
	{ name = "TQ_show_done_date", handler = "show_hide", display = "done date" },
	{ name = "TQ_show_urgency", handler = "show_hide", display = "urgency" },
	{ name = "TQ_show_backlink", handler = "show_hide", display = "backlink" },
	{ name = "TQ_show_edit_button", handler = "show_hide", display = "edit button" },
	{ name = "TQ_show_postpone_button", handler = "show_hide", display = "postpone button" },
	{ name = "TQ_show_task_count", handler = "show_hide", display = "task count" },
	{ name = "TQ_extra_instructions", handler = "add_value" },
}

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

local function frontmatter_lines(path)
	local lines = read_lines(path)
	if not lines or trim(lines[1]) ~= "---" then
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

local function parse_scalar(value)
	value = trim(value)
	if value == "" then
		return nil
	end

	local quoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
	if quoted ~= nil then
		return quoted
	end

	local lower = value:lower()
	if lower == "true" then
		return true
	elseif lower == "false" then
		return false
	elseif lower == "null" or lower == "~" then
		return nil
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

function M.frontmatter(path)
	local lines = frontmatter_lines(path)
	local props = {}
	local index = 1

	while index <= #lines do
		local key, value = lines[index]:match("^([%w_%-]+):%s*(.-)%s*$")
		if key then
			if value:match("^[|>]") then
				props[key], index = block_value(lines, index)
			else
				props[key] = parse_scalar(value)
				index = index + 1
			end
		else
			index = index + 1
		end
	end

	return props
end

local function query_file_path(opts)
	opts = opts or {}
	local source = opts.query_source or opts.querySource
	return opts.query_file_path
		or opts.queryFilePath
		or opts.source_path
		or opts.sourcePath
		or (source and source.source_path)
end

local function instruction_for(prop, value)
	if value == nil then
		return ""
	end

	if prop.handler == "instruction" then
		return value and prop.true_value or prop.false_value
	elseif prop.handler == "show_hide" then
		return (value and "show " or "hide ") .. prop.display
	elseif prop.handler == "add_value" then
		return type(value) == "string" and value or ""
	end

	return ""
end

function M.source(opts)
	local path = type(opts) == "string" and opts or query_file_path(opts)
	local props = M.frontmatter(path)
	local instructions = {}

	for _, prop in ipairs(PROPERTIES) do
		local instruction = instruction_for(prop, props[prop.name])
		if instruction ~= "" then
			table.insert(instructions, instruction)
		end
	end

	return table.concat(instructions, "\n")
end

function M.all_property_names()
	local names = {}
	for _, prop in ipairs(PROPERTIES) do
		table.insert(names, prop.name)
	end
	return names
end

return M
