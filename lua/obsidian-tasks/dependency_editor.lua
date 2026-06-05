local M = {}

local date = require("obsidian-tasks.date")
local cache = require("obsidian-tasks.cache")
local parser = require("obsidian-tasks.parser")
local source = require("obsidian-tasks.source")
local task_model = require("obsidian-tasks.task")
local task_search = require("obsidian-tasks.task_search")

local BOARD_ACTIONS_UNAVAILABLE = "board task actions are not wired yet"

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function rstrip(value)
	return (value or ""):gsub("%s+$", "")
end

local function get_config()
	local ok, plugin = pcall(require, "obsidian-tasks")
	if ok and plugin then
		return plugin.config or {}
	end
	return {}
end

local function reject_board_task(task)
	return require("obsidian-tasks.core").reject_board_task_action(task)
end

local function read_file_lines(file_path)
	local file = io.open(file_path, "r")
	if not file then
		return nil, "Cannot open file: " .. file_path
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
		return false, "Cannot write to file: " .. file_path
	end
	for _, line in ipairs(lines) do
		file:write(line .. "\n")
	end
	file:close()
	return true
end

local function realpath(path)
	if not path or path == "" then
		return path
	end
	local uv = vim.uv or vim.loop
	return (uv and uv.fs_realpath(path)) or path
end

local function loaded_buffer_for_file(file_path)
	local target = realpath(file_path)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and realpath(vim.api.nvim_buf_get_name(buf)) == target then
			return buf
		end
	end
	return nil
end

local function get_task_line(task)
	if not task or not task.file_path or not task.line_number then
		return nil, "Task has no source location"
	end

	local buf = loaded_buffer_for_file(task.file_path)
	if buf then
		return (vim.api.nvim_buf_get_lines(buf, task.line_number - 1, task.line_number, false)[1] or ""), nil, buf
	end

	local lines, err = read_file_lines(task.file_path)
	if not lines then
		return nil, err
	end
	return lines[task.line_number], nil, nil, lines
end

local function set_task_line(task, line)
	if not task or not task.file_path or not task.line_number then
		return false, "Task has no source location"
	end

	local buf = loaded_buffer_for_file(task.file_path)
	if buf then
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local line_number, locate_err = source.locate_in_lines(lines, task)
		if not line_number then
			return false, locate_err
		end
		vim.api.nvim_buf_set_lines(buf, line_number - 1, line_number, false, { line })
		vim.api.nvim_set_option_value("modified", true, { buf = buf })
		return true
	end

	local lines, err = read_file_lines(task.file_path)
	if not lines then
		return false, err
	end
	local line_number, locate_err = source.locate_in_lines(lines, task)
	if not line_number then
		return false, locate_err
	end
	lines[line_number] = line
	local ok, err = write_file_lines(task.file_path, lines)
	if ok then
		cache.on_file_changed(task.file_path)
	end
	return ok, err
end

local function all_ids(opts)
	opts = opts or {}
	local config = get_config()
	local vault_path = opts.vault_path or config.vault_path
	local ids = {}
	if not vault_path or vault_path == "" then
		return ids
	end

	for _, task in ipairs(require("obsidian-tasks.cache").tasks({
		vault_path = vault_path,
		global_filter = config.global_filter,
	})) do
		local id = trim(task.id)
		if id ~= "" then
			ids[id] = true
		end
	end
	return ids
end

function M.generate_id(task, opts)
	opts = opts or {}
	local used = opts.used_ids or all_ids(opts)
	local stamp = (opts.today or get_config().today or date.today()):gsub("%-", "")
	local line_part = tonumber(task and task.line_number) or 1
	local candidate = string.format("task-%s-%d", stamp, line_part)
	local index = 2
	while used[candidate] do
		candidate = string.format("task-%s-%d-%d", stamp, line_part, index)
		index = index + 1
	end
	used[candidate] = true
	return candidate
end

local function has_id(line)
	return (line or ""):find("🆔", 1, true) ~= nil
		or task_model.dataview_field_value(line, task_model.DATAVIEW_FIELD_KEYS.id) ~= nil
end

local function task_prefix(task)
	return string.format("%s%s [%s]", task.indentation or "", task.list_marker or "-", task.status_symbol or " ")
end

function M.add_id_to_line(line, id)
	if has_id(line) then
		return line
	end
	local parsed = task_model.parse_line({
		line = line,
		global_filter = "",
	})
	if parsed and parsed.task_format == "dataview" then
		return task_prefix(parsed) .. " " .. task_model.set_dataview_metadata(parsed.body or "", "id", id)
	end
	return rstrip(line) .. " 🆔 " .. id
end

function M.ensure_task_id(task, opts)
	local rejected = reject_board_task(task)
	if rejected ~= nil then
		return nil, BOARD_ACTIONS_UNAVAILABLE
	end

	opts = opts or {}
	if trim(task and task.id) ~= "" then
		return task.id, false
	end

	local line, err = get_task_line(task)
	if not line then
		return nil, err
	end

	local id = opts.id or M.generate_id(task, opts)
	local updated = M.add_id_to_line(line, id)
	local ok, write_err = set_task_line(task, updated)
	if not ok then
		return nil, write_err
	end

	task.id = id
	task.original_markdown = updated
	task.originalMarkdown = updated
	return id, true
end

local function split_csv(value)
	local items = {}
	for item in (value or ""):gmatch("[^,]+") do
		item = trim(item)
		if item ~= "" then
			table.insert(items, item)
		end
	end
	return items
end

function M.add_id_to_csv(value, id)
	local items = split_csv(value)
	for _, item in ipairs(items) do
		if item == id then
			return table.concat(items, ", ")
		end
	end
	table.insert(items, id)
	return table.concat(items, ", ")
end

function M.add_dependency_to_line(line, id)
	local parsed = task_model.parse_line({
		line = line,
		global_filter = "",
	})
	if not parsed then
		return nil, "Line is not a task"
	end
	for _, existing in ipairs(parsed.depends_on or parsed.dependsOn or {}) do
		if existing == id then
			return line
		end
	end

	if parsed.task_format == "dataview" then
		local value = table.concat(parsed.depends_on or parsed.dependsOn or {}, ", ")
		local body = task_model.set_dataview_metadata(parsed.body or "", "depends_on", M.add_id_to_csv(value, id))
		return task_prefix(parsed) .. " " .. body
	end

	local start_col, end_col, value = line:find("⛔%s*([%w_%-,%s]+)")
	if start_col then
		local prefix = line:sub(1, start_col - 1)
		local suffix = line:sub(end_col + 1)
		return prefix .. "⛔ " .. M.add_id_to_csv(value, id) .. suffix
	end

	return rstrip(line) .. " ⛔ " .. id
end

function M.current_task_at_cursor(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""

	local parsed = parser.parse_display_line(line)
	if parsed then
		local index_map = require("obsidian-tasks.core").task_index_map[buf] or {}
		local source = parsed.index and index_map[parsed.index]
		return source, row
	end

	local task = task_model.parse_line({
		line = line,
		file_path = vim.api.nvim_buf_get_name(buf),
		line_number = row,
		global_filter = "",
	})
	return task, row
end

function M.candidate_tasks(opts)
	return task_search.candidate_tasks(opts)
end

function M.select_dependency(opts, callback)
	opts = opts or {}
	local candidates = M.candidate_tasks(opts)
	if #candidates == 0 then
		vim.notify("No dependency candidates found", vim.log.levels.WARN)
		if callback then
			callback(nil)
		end
		return
	end

	vim.ui.select(candidates, {
		prompt = "Task dependency",
		format_item = task_search.format_candidate,
	}, function(task)
		if callback then
			callback(task)
		end
	end)
end

function M.add_dependency_to_task(task, dependency_id)
	local rejected = reject_board_task(task)
	if rejected ~= nil then
		return false, BOARD_ACTIONS_UNAVAILABLE
	end

	local line, err = get_task_line(task)
	if not line then
		return false, err
	end
	local updated, update_err = M.add_dependency_to_line(line, dependency_id)
	if not updated then
		return false, update_err
	end
	if updated == line then
		return true
	end
	return set_task_line(task, updated)
end

function M.add_dependency_at_cursor(opts)
	opts = opts or {}
	local buf = opts.buf or opts.buffer or vim.api.nvim_get_current_buf()
	local rejected = require("obsidian-tasks.core").reject_board_buffer_action(buf)
	if rejected ~= nil then
		return rejected
	end

	local current = opts.task or M.current_task_at_cursor(buf)
	if not current then
		vim.notify("Cursor is not on a task", vim.log.levels.ERROR)
		return false
	end

	local function add_target(target)
		if not target then
			return false
		end
		local id, id_err = M.ensure_task_id(target, opts)
		if not id then
			vim.notify(id_err or "Failed to create dependency id", vim.log.levels.ERROR)
			return false
		end
		local ok, err = M.add_dependency_to_task(current, id)
		if not ok then
			vim.notify(err or "Failed to add dependency", vim.log.levels.ERROR)
			return false
		end
		vim.notify("Added dependency: " .. id, vim.log.levels.INFO)
		return true
	end

	if opts.target_task then
		return add_target(opts.target_task)
	end

	M.select_dependency({
		vault_path = opts.vault_path,
		exclude = current,
	}, add_target)
	return true
end

return M
