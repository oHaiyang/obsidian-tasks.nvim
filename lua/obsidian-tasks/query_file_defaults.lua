local M = {}

local frontmatter = require("obsidian-tasks.frontmatter")

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

local function frontmatter_range(lines)
	if trim(lines[1]) ~= "---" then
		return nil, nil
	end

	for index = 2, #lines do
		local trimmed = trim(lines[index])
		if trimmed == "---" or trimmed == "..." then
			return 1, index
		end
	end

	return nil, nil
end

local function copy_lines(lines)
	local copied = {}
	for _, line in ipairs(lines or {}) do
		table.insert(copied, line)
	end
	return copied
end

local function is_empty_buffer_lines(lines)
	return #lines == 0 or (#lines == 1 and lines[1] == "")
end

local function frontmatter_keys(lines, start_index, end_index)
	local keys = {}
	for index = start_index + 1, end_index - 1 do
		local key = lines[index]:match("^([%w_%-]+):%s*")
		if key then
			keys[key] = true
		end
	end
	return keys
end

local function missing_property_lines(existing_keys)
	local missing = {}
	for _, name in ipairs(M.all_property_names_sorted()) do
		if not existing_keys[name] then
			table.insert(missing, name .. ":")
		end
	end
	return missing
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
	return frontmatter.parse_file(path)
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

function M.all_property_names_sorted()
	local names = M.all_property_names()
	table.sort(names)
	return names
end

function M.add_all_properties_to_lines(lines)
	lines = copy_lines(lines)

	local start_index, end_index = frontmatter_range(lines)
	if start_index then
		local missing = missing_property_lines(frontmatter_keys(lines, start_index, end_index))
		if #missing == 0 then
			return lines, 0
		end

		local updated = {}
		for index = 1, end_index - 1 do
			table.insert(updated, lines[index])
		end
		for _, line in ipairs(missing) do
			table.insert(updated, line)
		end
		for index = end_index, #lines do
			table.insert(updated, lines[index])
		end
		return updated, #missing
	end

	local missing = missing_property_lines({})
	local updated = { "---" }
	for _, line in ipairs(missing) do
		table.insert(updated, line)
	end
	table.insert(updated, "---")

	if not is_empty_buffer_lines(lines) then
		table.insert(updated, "")
		for _, line in ipairs(lines) do
			table.insert(updated, line)
		end
	end

	return updated, #missing
end

function M.add_all_properties_to_buffer(buf)
	buf = buf or 0
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local updated, added_count = M.add_all_properties_to_lines(lines)

	if added_count == 0 then
		vim.notify("All supported properties are already present.", vim.log.levels.INFO)
		return 0
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, updated)
	vim.notify("Properties updated successfully.", vim.log.levels.INFO)
	return added_count
end

return M
