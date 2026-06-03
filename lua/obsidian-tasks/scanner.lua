local M = {}

local frontmatter = require("obsidian-tasks.frontmatter")
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

local function html_comment_state(line, in_comment)
	local search_from = 1
	local current = in_comment
	while true do
		if current then
			local close_at = line:find("-->", search_from, true)
			if not close_at then
				return true
			end
			current = false
			search_from = close_at + 3
		else
			local open_at = line:find("<!--", search_from, true)
			if not open_at then
				return false
			end
			local close_at = line:find("-->", open_at + 4, true)
			if not close_at then
				return true
			end
			search_from = close_at + 3
		end
	end
end

local function obsidian_comment_state(line, in_comment)
	local search_from = 1
	local current = in_comment
	while true do
		local marker = line:find("%%%%", search_from)
		if not marker then
			return current
		end
		current = not current
		search_from = marker + 2
	end
end

local function heading_text(line)
	return line:match("^%s*#+%s+(.+)$")
end

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function parse_list_item(line)
	local indentation, list_marker, body = line:match("^([%s\t>]*)([-*+])%s+(.*)$")
	if not indentation then
		indentation, list_marker, body = line:match("^([%s\t>]*)(%d+[%.%)])%s+(.*)$")
	end
	if not indentation then
		return nil
	end

	local status_symbol, description = body:match("^%[(.)%]%s*(.*)$")
	return {
		original_markdown = line,
		originalMarkdown = line,
		indentation = indentation,
		list_marker = list_marker,
		listMarker = list_marker,
		status_symbol = status_symbol,
		statusCharacter = status_symbol,
		description = trim(description or body),
		children = {},
	}
end

local function blockquote_depth(line)
	local prefix = line:match("^%s*([>%s]*)") or ""
	local count = 0
	for _ in prefix:gmatch(">") do
		count = count + 1
	end
	return count
end

local function callout_type(line)
	return line:match("^%s*>%s*%[!([%w%-]+)%]")
end

local function list_indent_depth(indentation)
	indentation = (indentation or ""):gsub("\t", "    ")
	local last_blockquote = nil
	local start = 1
	while true do
		local found = indentation:find(">", start, true)
		if not found then
			break
		end
		last_blockquote = found
		start = found + 1
	end
	if last_blockquote then
		indentation = indentation:sub(last_blockquote + 1)
	end
	return #indentation
end

local function attach_to_tree(stack, item)
	item.indent_depth = list_indent_depth(item.indentation)
	while #stack > 0 and (stack[#stack].indent_depth or 0) >= item.indent_depth do
		table.remove(stack)
	end

	local parent = stack[#stack]
	item.parent = parent
	if parent then
		table.insert(parent.children, item)
	end
	table.insert(stack, item)
end

function M.scan_file(path, opts)
	opts = opts or {}
	local lines = read_lines(path)
	if not lines then
		return {}
	end

	local tasks = {}
	local in_fence = false
	local in_html_comment = false
	local in_obsidian_comment = false
	local current_heading = nil
	local current_callout = nil
	local list_stack = {}
	local properties = frontmatter.parse(lines)
	local file_fields = frontmatter.file_fields(properties)

	for line_number, line in ipairs(lines) do
		if is_fence(line) then
			in_fence = not in_fence
		elseif not in_fence then
			local next_obsidian_comment = obsidian_comment_state(line, in_obsidian_comment)
			local skip_obsidian_line = in_obsidian_comment or line:find("%%%%") ~= nil
			in_obsidian_comment = next_obsidian_comment
			if skip_obsidian_line then
				goto continue
			end

			local next_html_comment = html_comment_state(line, in_html_comment)
			local skip_line = in_html_comment or line:find("<!--", 1, true) ~= nil
			in_html_comment = next_html_comment
			if skip_line then
				goto continue
			end

			local callout = callout_type(line)
			if callout then
				current_callout = callout:lower()
			elseif blockquote_depth(line) == 0 then
				current_callout = nil
			end

			local heading = heading_text(line)
			if heading then
				current_heading = heading
			else
				local list_item = parse_list_item(line)
				if list_item then
					list_item.file_path = path
					list_item.line_number = line_number
					list_item.heading = current_heading
					list_item.blockquote_depth = blockquote_depth(line)
					list_item.is_blockquote = list_item.blockquote_depth > 0
					list_item.callout = current_callout
					attach_to_tree(list_stack, list_item)
				end

				local task = task_model.parse_line({
					line = line,
					file_path = path,
					line_number = line_number,
					heading = current_heading,
					global_filter = opts.global_filter,
					remove_global_filter = opts.remove_global_filter or opts.removeGlobalFilter,
					today = opts.today,
					frontmatter = file_fields.frontmatter,
					properties = file_fields.properties,
					file_tags = file_fields.tags,
					file_aliases = file_fields.aliases,
					file_cssclasses = file_fields.cssclasses,
				})

				if task then
					task.blockquote_depth = blockquote_depth(line)
					task.blockquoteDepth = task.blockquote_depth
					task.is_blockquote = task.blockquote_depth > 0
					task.isBlockquote = task.is_blockquote
					task.callout = current_callout
					if list_item then
						list_item.task = task
						task.list_item = list_item
						task.listItem = list_item
					end
					table.insert(tasks, task)
				end
			end
		end
		::continue::
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
