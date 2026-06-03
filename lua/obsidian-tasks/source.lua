local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function read_file_lines(file_path)
	local file = io.open(file_path, "r")
	if not file then
		return nil, "Cannot open file: " .. tostring(file_path)
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()
	return lines
end

local function write_file_lines(file_path, lines)
	local file = io.open(file_path, "w")
	if not file then
		return false, "Cannot write to file: " .. tostring(file_path)
	end
	for _, line in ipairs(lines or {}) do
		file:write(line .. "\n")
	end
	file:close()
	return true
end

local function same_original(line, task)
	return trim(task and (task.original_markdown or task.originalMarkdown)) ~= ""
		and line == (task.original_markdown or task.originalMarkdown)
end

local function parsed_line(line, task, line_number)
	local task_model = require("obsidian-tasks.task")
	return task_model.parse_line({
		line = line,
		file_path = task and task.file_path,
		line_number = line_number,
		global_filter = "",
		task_format = task and (task.task_format or task.taskFormat),
	})
end

local function same_id(line, task, line_number)
	local id = trim(task and task.id)
	if id == "" then
		return false
	end
	local parsed = parsed_line(line, task, line_number)
	return parsed and trim(parsed.id) == id
end

local function same_block_link(line, task, line_number)
	local block_link = trim(task and task.block_link)
	if block_link == "" then
		return false
	end
	local parsed = parsed_line(line, task, line_number)
	return parsed and trim(parsed.block_link) == block_link
end

local function unique_match(lines, predicate)
	local found
	for index, line in ipairs(lines or {}) do
		if predicate(line, index) then
			if found then
				return nil, "ambiguous"
			end
			found = index
		end
	end
	return found, found and nil or "not_found"
end

function M.signature(task)
	task = task or {}
	return {
		file_path = task.file_path,
		line_number = task.line_number,
		id = task.id,
		block_link = task.block_link,
		original_markdown = task.original_markdown or task.originalMarkdown,
		description = task.description or task.text,
	}
end

function M.enrich(task)
	if not task then
		return task
	end
	task.source = M.signature(task)
	task.source_signature = task.source
	task.sourceSignature = task.source
	return task
end

function M.locate_in_lines(lines, task)
	if not task then
		return nil, "Task has no source metadata"
	end

	local original_line = tonumber(task.line_number)
	if original_line and lines[original_line] then
		local line = lines[original_line]
		if same_original(line, task) then
			return original_line, "original line"
		end
		if same_id(line, task, original_line) then
			return original_line, "id at original line"
		end
		if same_block_link(line, task, original_line) then
			return original_line, "block link at original line"
		end
	end

	local id = trim(task.id)
	if id ~= "" then
		local index, err = unique_match(lines, function(line, line_number)
			return same_id(line, task, line_number)
		end)
		if index then
			return index, "id"
		end
		if err == "ambiguous" then
			return nil, "Multiple tasks have id `" .. id .. "`"
		end
	end

	local block_link = trim(task.block_link)
	if block_link ~= "" then
		local index, err = unique_match(lines, function(line, line_number)
			return same_block_link(line, task, line_number)
		end)
		if index then
			return index, "block link"
		end
		if err == "ambiguous" then
			return nil, "Multiple tasks have block link `" .. block_link .. "`"
		end
	end

	local original_markdown = task.original_markdown or task.originalMarkdown
	if trim(original_markdown) ~= "" then
		local index, err = unique_match(lines, function(line)
			return line == original_markdown
		end)
		if index then
			return index, "original markdown"
		end
		if err == "ambiguous" then
			return nil, "Multiple tasks match the original markdown"
		end
	end

	return nil, "Task source line changed; refresh results before editing"
end

function M.read_lines(file_path)
	return read_file_lines(file_path)
end

function M.write_lines(file_path, lines)
	return write_file_lines(file_path, lines)
end

function M.locate_in_file(task)
	local file_path = task and task.file_path
	if not file_path or file_path == "" then
		return nil, "Task has no source file"
	end
	local lines, err = read_file_lines(file_path)
	if not lines then
		return nil, err
	end
	local line_number, locate_err = M.locate_in_lines(lines, task)
	return line_number, locate_err, lines
end

return M
