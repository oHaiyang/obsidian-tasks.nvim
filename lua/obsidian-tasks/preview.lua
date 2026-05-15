local M = {}

M.namespace = vim.api.nvim_create_namespace("obsidian_tasks_preview")
M.enabled = {}

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function filename(path)
	return (path or ""):match("([^/]+)$") or path or ""
end

local function task_line(task)
	local text = task.description or task.text or task.body or ""
	local source = filename(task.file_path)
	if task.line_number then
		source = source .. "#L" .. task.line_number
	end
	return string.format("  %s %s    %s", task.status or "[ ]", text, source)
end

local function preview_lines_for(source, opts)
	opts = opts or {}
	local config = get_config()
	local query = require("obsidian-tasks.query")
	local scanner = require("obsidian-tasks.scanner")
	local sorter = require("obsidian-tasks.sort")

	local plan = query.parse(source.query, {
		today = opts.today,
	})

	if #plan.errors > 0 then
		return {
			{
				{ "Tasks preview: query error - " .. (plan.errors[1].message or "unknown error"), "DiagnosticError" },
			},
		}
	end

	local tasks = scanner.scan_vault({
		vault_path = config.vault_path,
		global_filter = config.global_filter,
	})
	tasks = query.filter_tasks(tasks, plan)
	if #plan.sorts > 0 then
		tasks = sorter.apply(tasks, plan.sorts)
	end

	local limit = opts.limit or config.preview_limit or 5
	local lines = {
		{
			{ string.format("Tasks preview: Showing %d of %d", math.min(#tasks, limit), #tasks), "Comment" },
		},
	}

	for index = 1, math.min(#tasks, limit) do
		table.insert(lines, {
			{ task_line(tasks[index]), "Comment" },
		})
	end

	return lines
end

function M.refresh_buffer(buf, opts)
	opts = opts or {}
	buf = buf or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)

	local sources = require("obsidian-tasks.query_block").scan_buffer(buf)
	for _, source in ipairs(sources) do
		local ok, virt_lines = pcall(preview_lines_for, source, opts)
		if not ok then
			virt_lines = {
				{
					{ "Tasks preview: " .. tostring(virt_lines), "DiagnosticError" },
				},
			}
		end

		vim.api.nvim_buf_set_extmark(buf, M.namespace, math.max(source.end_line - 1, 0), 0, {
			virt_lines = virt_lines,
			virt_lines_above = false,
		})
	end
end

function M.clear(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
	M.enabled[buf] = nil
end

function M.toggle(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if M.enabled[buf] then
		M.clear(buf)
		return false
	end

	M.enabled[buf] = true
	M.refresh_buffer(buf)
	return true
end

return M
