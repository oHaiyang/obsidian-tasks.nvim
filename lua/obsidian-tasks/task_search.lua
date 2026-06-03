local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

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

function M.same_source(left, right)
	return left
		and right
		and realpath(left.file_path or "") == realpath(right.file_path or "")
		and left.line_number == right.line_number
end

function M.file_label(task)
	if task and task.file and task.file.filename then
		return task.file.filename
	end
	return ((task and task.file_path) or ""):match("([^/]+)$") or ""
end

function M.description(task)
	return (task and (task.description or task.text or task.display_text)) or ""
end

function M.task_id(task)
	return trim(task and task.id)
end

function M.candidate_tasks(opts)
	opts = opts or {}
	local config = get_config()
	local vault_path = opts.vault_path or config.vault_path
	if not vault_path or vault_path == "" then
		return {}
	end

	local tasks = {}
	for _, task in ipairs(require("obsidian-tasks.scanner").scan_vault({
		vault_path = vault_path,
		global_filter = opts.global_filter or opts.globalFilter or config.global_filter,
	})) do
		if not opts.exclude or not M.same_source(task, opts.exclude) then
			table.insert(tasks, task)
		end
	end
	table.sort(tasks, function(left, right)
		if left.file_path == right.file_path then
			return (left.line_number or 0) < (right.line_number or 0)
		end
		return (left.file_path or "") < (right.file_path or "")
	end)
	return tasks
end

function M.format_candidate(task, opts)
	opts = opts or {}
	local id = M.task_id(task)
	local id_text = id ~= "" and ("🆔 " .. id) or (opts.no_id_label or "new id")
	return string.format("%s  %s:%s  %s", M.description(task), M.file_label(task), task.line_number or "?", id_text)
end

function M.completion_item(task, opts)
	opts = opts or {}
	local id = M.task_id(task)
	if id == "" and opts.require_id ~= false then
		return nil
	end

	local word = id
	if word == "" then
		word = opts.no_id_word or ""
	end

	return {
		word = word,
		abbr = M.format_candidate(task, { no_id_label = opts.no_id_label or "needs id" }),
		menu = id ~= "" and (opts.menu or "depends on") or "needs id",
		filter_text = {
			id,
			M.description(task),
			M.file_label(task),
			task.file_path or "",
		},
		data = {
			kind = "task",
			id = id,
			needs_id = id == "",
			task = task,
			file_path = task.file_path,
			line_number = task.line_number,
		},
	}
end

return M
