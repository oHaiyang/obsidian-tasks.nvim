local M = {}

local task_model = require("obsidian-tasks.task")

local function is_markdown_file(path)
	return path:sub(-3) == ".md"
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

local function is_fence(line)
	return line:match("^%s*```") or line:match("^%s*~~~")
end

local function heading_text(line)
	return line:match("^%s*#+%s+(.+)$")
end

function M.scan_file(path, opts)
	opts = opts or {}
	local lines = read_lines(path)
	if not lines then
		return {}
	end

	local tasks = {}
	local in_fence = false
	local current_heading = nil

	for line_number, line in ipairs(lines) do
		if is_fence(line) then
			in_fence = not in_fence
		elseif not in_fence then
			local heading = heading_text(line)
			if heading then
				current_heading = heading
			else
				local task = task_model.parse_line({
					line = line,
					file_path = path,
					line_number = line_number,
					heading = current_heading,
					global_filter = opts.global_filter,
				})

				if task then
					table.insert(tasks, task)
				end
			end
		end
	end

	return tasks
end

function M.scan_vault(opts)
	opts = opts or {}
	local vault_path = opts.vault_path
	if not vault_path or vault_path == "" then
		return {}
	end

	local tasks = {}
	for _, path in ipairs(markdown_files(vault_path)) do
		if is_markdown_file(path) then
			for _, task in ipairs(M.scan_file(path, opts)) do
				table.insert(tasks, task)
			end
		end
	end

	return tasks
end

return M
