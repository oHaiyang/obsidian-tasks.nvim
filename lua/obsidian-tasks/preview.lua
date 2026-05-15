local M = {}

M.namespace = vim.api.nvim_create_namespace("obsidian_tasks_preview")
M.enabled = {}

local function get_config()
	return require("obsidian-tasks").config or {}
end

local function filename(path)
	return (path or ""):match("([^/]+)$") or path or ""
end

local function task_line(task, opts)
	opts = opts or {}
	local display = require("obsidian-tasks.display")
	local text = display.format_task_body(task, opts)
	if display.should_show(opts, "backlink", true) then
		local source = filename(task.file_path)
		if task.line_number then
			source = source .. "#L" .. task.line_number
		end
		return string.format("  %s %s    %s", task.status or "[ ]", text, source)
	end
	return string.format("  %s %s", task.status or "[ ]", text)
end

local function preview_lines_for(source, opts)
	opts = opts or {}
	local config = get_config()
	local query = require("obsidian-tasks.query")
	local scanner = require("obsidian-tasks.scanner")
	local sorter = require("obsidian-tasks.sort")

	local query_opts = {
		today = opts.today,
		config = config,
		query_source = source,
	}
	local composition = query.compose(source.query, query_opts)
	local plan = query.parse(composition.source, query_opts)
	plan.composition = composition
	plan.original_query = source.query

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
	local display = require("obsidian-tasks.display")
	local preview_opts = {
		layout = plan.layout,
		query_plan = plan,
	}
	local lines = {}
	if display.should_show(preview_opts, "task count", true) then
		table.insert(lines, {
			{ string.format("Tasks preview: Showing %d of %d", math.min(#tasks, limit), #tasks), "Comment" },
		})
	end

	for index = 1, math.min(#tasks, limit) do
		table.insert(lines, {
			{ task_line(tasks[index], preview_opts), "Comment" },
		})
	end

	if #lines == 0 then
		table.insert(lines, {
			{ "Tasks preview", "Comment" },
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
