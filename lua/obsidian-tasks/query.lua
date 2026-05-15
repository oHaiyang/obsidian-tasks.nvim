local M = {}

local date = require("obsidian-tasks.date")
local dependencies = require("obsidian-tasks.dependencies")
local sort = require("obsidian-tasks.sort")
local status = require("obsidian-tasks.status")

M.DEFAULT_PRESETS = {
	this_file = "path includes {{query.file.path}}",
	this_folder = "folder includes {{query.file.folder}}",
	this_root = "root includes {{query.file.root}}",
}

local PRIORITIES = {
	highest = true,
	high = true,
	medium = true,
	normal = true,
	none = true,
	low = true,
	lowest = true,
}

local DATE_FIELDS = {
	due = true,
	scheduled = true,
	start = true,
	starts = true,
	done = true,
	created = true,
	cancelled = true,
	canceled = true,
	happens = true,
}

local SORT_FIELDS = {
	status = true,
	["status.type"] = true,
	priority = true,
	due = true,
	scheduled = true,
	start = true,
	done = true,
	created = true,
	cancelled = true,
	happens = true,
	path = true,
	file = true,
	filename = true,
	heading = true,
	description = true,
}

local GROUP_FIELDS = {
	status = true,
	["status.type"] = true,
	priority = true,
	file = true,
	filename = true,
	heading = true,
	due = true,
	scheduled = true,
	start = true,
	done = true,
	happens = true,
}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function basename(path)
	return (path or ""):match("([^/]+)$") or path or ""
end

local function dirname(path)
	local dir = (path or ""):match("^(.*[/])[^/]*$")
	if dir == nil or dir == "" then
		return "/"
	end
	return dir
end

local function rootname(path)
	local root = (path or ""):match("^([^/]+/)")
	return root or "/"
end

local function without_extension(path)
	return (path or ""):gsub("%.[^%.%/]+$", "")
end

local function lower(value)
	return trim(value):lower()
end

local function normalize_priority(value)
	value = lower(value)
	if value == "none" then
		return "normal"
	end
	if PRIORITIES[value] then
		return value
	end
	return nil
end

local function normalize_status(value)
	value = trim(value)
	local inner = value:match("^%[(.)%]$")
	return inner or value
end

local function normalize_status_type(value)
	return trim(value):upper():gsub("%s+", "_"):gsub("%-", "_")
end

local function add_error(plan, line_number, line, message)
	table.insert(plan.errors, {
		line_number = line_number,
		line = line,
		message = message,
	})
end

local function add_filter(plan, filter)
	table.insert(plan.filters, filter)
end

local function normalize_layout_field(field)
	field = lower(field):gsub("%s+", " ")
	if field == "backlinks" then
		return "backlink"
	end
	return field
end

local parse_line

local function config_from_opts(opts)
	opts = opts or {}
	if opts.config then
		return opts.config
	end
	local ok, plugin = pcall(require, "obsidian-tasks")
	return ok and plugin.config or {}
end

local function preset_map(opts)
	opts = opts or {}
	local config = config_from_opts(opts)
	local presets = vim.tbl_extend("force", M.DEFAULT_PRESETS, {})
	for key, value in pairs((config and (config.presets or config.query_presets or config.queryPresets)) or {}) do
		presets[key] = value
	end
	return presets
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

local function query_file_context(opts)
	local path = query_file_path(opts)
	if not path or path == "" then
		return nil
	end

	local filename = basename(path)
	return {
		path = path,
		path_without_extension = without_extension(path),
		pathWithoutExtension = without_extension(path),
		root = rootname(path),
		folder = dirname(path),
		filename = filename,
		filename_without_extension = without_extension(filename),
		filenameWithoutExtension = without_extension(filename),
	}
end

local function placeholder_value(name, opts, query_file)
	name = trim(name)
	local preset_name = name:match("^preset%.(.+)$")
	if preset_name then
		local preset = preset_map(opts)[preset_name]
		if not preset then
			return nil, "Unknown preset placeholder: " .. preset_name
		end
		return tostring(preset)
	end

	local file_field = name:match("^query%.file%.(.+)$")
	if file_field then
		if not query_file then
			return nil, "The query uses " .. name .. " but no query file path is available"
		end
		local value = query_file[file_field]
		if value == nil then
			return nil, "Unknown query file placeholder: " .. name
		end
		return tostring(value)
	end

	return nil, "Unknown placeholder: " .. name
end

local function expand_placeholders(source, opts, query_file)
	local expanded = tostring(source or "")
	local errors = {}

	for _ = 1, 10 do
		local changed = false
		local next_value = expanded:gsub("{{%s*([^{}]+)%s*}}", function(name)
			local value, err = placeholder_value(name, opts, query_file)
			if not value then
				table.insert(errors, err)
				return "{{" .. name .. "}}"
			end
			changed = true
			return value
		end)

		expanded = next_value
		if #errors > 0 then
			return expanded, errors
		end
		if not changed then
			return expanded, errors
		end
	end

	table.insert(errors, "Placeholder expansion did not converge")
	return expanded, errors
end

local function global_query_source(opts)
	local config = config_from_opts(opts)
	return tostring((config and (config.global_query or config.globalQuery)) or "")
end

local function strip_ignore_global_query(source)
	local lines = {}
	for line in (tostring(source or "") .. "\n"):gmatch("(.-)\n") do
		if not trim(line):lower():match("^ignore%s+global%s+query") then
			table.insert(lines, line)
		end
	end
	return table.concat(lines, "\n")
end

local function join_sources(sources)
	local result = {}
	for _, source in ipairs(sources or {}) do
		source = tostring(source or "")
		if trim(source) ~= "" then
			table.insert(result, source)
		end
	end
	return table.concat(result, "\n")
end

local function add_preset(plan, line_number, original_line, name, opts)
	name = trim(name)
	local presets = preset_map(opts)
	local preset = presets[name]
	if not preset then
		local names = {}
		for key, _ in pairs(presets) do
			table.insert(names, key)
		end
		table.sort(names)
		local message = "Unknown preset: " .. name
		if #names > 0 then
			message = message .. ". Available presets: " .. table.concat(names, ", ")
		end
		add_error(plan, line_number, original_line, message)
		return
	end

	local source = tostring(preset or "")
	local expanded, placeholder_errors = expand_placeholders(source, opts, query_file_context(opts))
	if #placeholder_errors > 0 then
		for _, err in ipairs(placeholder_errors) do
			add_error(plan, line_number, original_line, err)
		end
		return
	end

	for line in (expanded .. "\n"):gmatch("(.-)\n") do
		parse_line(plan, line_number, line, opts)
	end
end

local function parse_regex_expr(expr)
	expr = trim(expr)
	local pattern, flags = expr:match("^/(.*)/([%a]*)$")
	if not pattern then
		return nil, "Expected /pattern/flags"
	end

	local vim_pattern = "\\v" .. pattern
	if flags:find("i", 1, true) then
		vim_pattern = "\\c" .. vim_pattern
	end

	local ok, compiled = pcall(vim.regex, vim_pattern)
	if not ok then
		return nil, compiled
	end

	return {
		pattern = pattern,
		flags = flags,
		compiled = compiled,
	}
end

local function compile_lua_filter(expr)
	local source = "return function(task, query) return (" .. expr .. ") end"
	local env = {
		string = string,
		table = table,
		math = math,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		ipairs = ipairs,
		pairs = pairs,
	}
	local chunk, err = load(source, "obsidian-tasks-filter", "t", env)
	if not chunk then
		return nil, err
	end

	local ok, fn_or_err = pcall(chunk)
	if not ok then
		return nil, fn_or_err
	end
	return fn_or_err
end

local function add_lua_filter(plan, line_number, original_line, expr, opts)
	opts = opts or {}
	local config = opts.config
	if not config then
		local ok, plugin = pcall(require, "obsidian-tasks")
		config = ok and plugin.config or {}
	end
	if not (opts.enable_lua_filters or opts.enableLuaFilters or config.enable_lua_filters or config.enableLuaFilters) then
		add_error(plan, line_number, original_line, "Lua function filters are disabled. Set enable_lua_filters = true.")
		return
	end

	local fn, err = compile_lua_filter(expr)
	if not fn then
		add_error(plan, line_number, original_line, "Invalid Lua function filter: " .. tostring(err))
		return
	end

	add_filter(plan, {
		type = "function",
		expr = expr,
		fn = fn,
	})
end

local function add_date_filter(plan, line_number, original_line, field, op, expr, opts)
	field = lower(field)
	if not DATE_FIELDS[field] then
		add_error(plan, line_number, original_line, "Unsupported date field: " .. field)
		return
	end

	local value = date.parse_date_expr(expr, opts)
	if not value then
		add_error(plan, line_number, original_line, "Invalid date expression: " .. trim(expr))
		return
	end

	add_filter(plan, {
		type = "date_compare",
		field = field,
		op = op,
		value = value,
	})
end

local function add_date_exists_filter(plan, line_number, original_line, field, exists)
	field = lower(field)
	if not DATE_FIELDS[field] then
		add_error(plan, line_number, original_line, "Unsupported date field: " .. field)
		return
	end

	add_filter(plan, {
		type = "date_exists",
		field = field,
		exists = exists,
	})
end

local function matching_close_index(value, open_index)
	local depth = 0
	local quote = nil
	local escaped = false

	for index = open_index, #value do
		local char = value:sub(index, index)
		if quote then
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == quote then
				quote = nil
			end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char == "(" then
			depth = depth + 1
		elseif char == ")" then
			depth = depth - 1
			if depth == 0 then
				return index
			elseif depth < 0 then
				return nil
			end
		end
	end

	return nil
end

local function strip_outer_parentheses(value)
	value = trim(value)
	while value:sub(1, 1) == "(" do
		local close_index = matching_close_index(value, 1)
		if close_index ~= #value then
			break
		end
		value = trim(value:sub(2, #value - 1))
	end
	return value
end

local function operator_at(value, index, operator)
	if value:sub(index, index + #operator - 1) ~= operator then
		return false
	end

	local before = index == 1 and "" or value:sub(index - 1, index - 1)
	local after_index = index + #operator
	local after = after_index > #value and "" or value:sub(after_index, after_index)
	local before_ok = before == "" or before:match("%s") ~= nil or before == "("
	local after_ok = after == "" or after:match("%s") ~= nil or after == "("
	return before_ok and after_ok
end

local function find_top_level_operator(value, operator)
	local depth = 0
	local quote = nil
	local escaped = false

	for index = 1, #value do
		local char = value:sub(index, index)
		if quote then
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == quote then
				quote = nil
			end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char == "(" then
			depth = depth + 1
		elseif char == ")" then
			depth = depth - 1
			if depth < 0 then
				return nil, "Unmatched closing parenthesis"
			end
		elseif depth == 0 and operator_at(value, index, operator) then
			return index
		end
	end

	if depth > 0 then
		return nil, "Unmatched opening parenthesis"
	end
	return nil
end

local function boolean_operand_shape(value)
	value = trim(value)
	return value:sub(1, 1) == "(" or value:match("^NOT%s+%(") ~= nil
end

local function parse_subfilter(value, opts)
	local temp = {
		raw = value,
		filters = {},
		sorts = {},
		group_by = {},
		limit = nil,
		group_limit = nil,
		ignore_global_query = false,
		explain = false,
		layout = {
			show = {},
		},
		layout_statements = {},
		errors = {},
		warnings = {},
	}

	local sub_opts = vim.tbl_extend("force", opts or {}, {
		disable_boolean = true,
	})
	parse_line(temp, 0, value, sub_opts)

	if #temp.errors > 0 then
		return nil, temp.errors[1].message
	end
	if #temp.filters ~= 1 or #temp.sorts > 0 or #temp.group_by > 0 or temp.limit ~= nil then
		return nil, "Boolean operands must resolve to exactly one filter"
	end
	if temp.filters[1].type == "or" then
		return nil, "`OR` line separators cannot be used inside Boolean operands"
	end

	return temp.filters[1]
end

local function parse_boolean_expr(value, opts)
	value = trim(value)
	if value == "" then
		return nil, "Empty Boolean expression", false
	end

	local stripped = strip_outer_parentheses(value)
	if stripped ~= value then
		local node, err, is_boolean = parse_boolean_expr(stripped, opts)
		return node, err, is_boolean or true
	end

	if value:match("^NOT%s+") then
		local rest = trim(value:gsub("^NOT%s+", "", 1))
		if rest == "" then
			return nil, "NOT must be followed by a filter or expression", true
		end
		local child, err = parse_boolean_expr(rest, opts)
		if not child then
			return nil, err, true
		end
		return {
			type = "not",
			child = child,
		}, nil, true
	end

	for _, operator in ipairs({ "OR", "AND" }) do
		local index, err = find_top_level_operator(value, operator)
		if err then
			return nil, err, true
		end
		if index then
			local left = trim(value:sub(1, index - 1))
			local right = trim(value:sub(index + #operator))
			if left == "" or right == "" then
				return nil, "Boolean operator " .. operator .. " requires filters on both sides", true
			end
			if not boolean_operand_shape(left) or not boolean_operand_shape(right) then
				break
			end

			local left_node, left_err = parse_boolean_expr(left, opts)
			if not left_node then
				return nil, left_err, true
			end
			local right_node, right_err = parse_boolean_expr(right, opts)
			if not right_node then
				return nil, right_err, true
			end
			return {
				type = operator:lower(),
				left = left_node,
				right = right_node,
			}, nil, true
		end
	end

	local filter, err = parse_subfilter(value, opts)
	if not filter then
		return nil, err, false
	end
	return {
		type = "filter",
		filter = filter,
	}, nil, false
end

local function add_boolean_filter(plan, line_number, original_line, opts)
	local node, err, is_boolean = parse_boolean_expr(original_line, opts)
	if not node and is_boolean then
		add_error(plan, line_number, original_line, "Invalid Boolean expression: " .. tostring(err))
		return true
	end

	if node and (is_boolean or trim(original_line):sub(1, 1) == "(") then
		add_filter(plan, {
			type = "boolean",
			node = node,
		})
		return true
	end

	return false
end

function parse_line(plan, line_number, line, opts)
	opts = opts or {}
	plan.layout = plan.layout or { show = {} }
	plan.layout.show = plan.layout.show or {}
	plan.layout_statements = plan.layout_statements or {}
	local original_line = line
	line = trim(line)
	if line == "" or line:match("^#") then
		return
	end

	local line_lower = line:lower()

	if line_lower:match("^ignore%s+global%s+query") then
		plan.ignore_global_query = true
		return
	end

	if line_lower:match("^explain") then
		plan.explain = true
		plan.layout.explain = true
		return
	end

	if line_lower:match("^short") then
		plan.layout.short_mode = true
		table.insert(plan.layout_statements, { type = "short_mode", value = true, line = original_line })
		return
	elseif line_lower:match("^full") then
		plan.layout.short_mode = false
		table.insert(plan.layout_statements, { type = "short_mode", value = false, line = original_line })
		return
	end

	local visibility, layout_field = line_lower:match("^(show)%s+(.+)$")
	if not visibility then
		visibility, layout_field = line_lower:match("^(hide)%s+(.+)$")
	end
	if visibility and layout_field then
		layout_field = normalize_layout_field(layout_field)
		plan.layout.show[layout_field] = visibility == "show"
		table.insert(plan.layout_statements, {
			type = "visibility",
			field = layout_field,
			value = visibility == "show",
			line = original_line,
		})
		return
	end

	if line == "OR" then
		add_filter(plan, { type = "or" })
		return
	end

	if not opts.disable_boolean and add_boolean_filter(plan, line_number, line, opts) then
		return
	end

	local preset_name = line:match("^preset%s+(.+)$")
	if preset_name then
		add_preset(plan, line_number, original_line, preset_name, opts)
		return
	end

	local function_expr = line:match("^filter%s+by%s+lua%s+(.+)$") or line:match("^filter%s+by%s+function%s+(.+)$")
	if function_expr then
		add_lua_filter(plan, line_number, original_line, function_expr, opts)
		return
	end

	if line_lower == "not done" then
		add_filter(plan, { type = "done", value = false })
		return
	elseif line_lower == "done" then
		add_filter(plan, { type = "done", value = true })
		return
	end

	local value = line:match("^status%s+is%s+not%s+(.+)$")
	if value then
		add_filter(plan, { type = "status", op = "is_not", value = normalize_status(value) })
		return
	end

	value = line:match("^status%s+is%s+(.+)$")
	if value then
		add_filter(plan, { type = "status", op = "is", value = normalize_status(value) })
		return
	end

	value = line_lower:match("^status[%.%s]+type%s+is%s+not%s+(.+)$")
	if value then
		add_filter(plan, { type = "status_type", op = "is_not", value = normalize_status_type(value) })
		return
	end

	value = line_lower:match("^status[%.%s]+type%s+is%s+(.+)$")
	if value then
		add_filter(plan, { type = "status_type", op = "is", value = normalize_status_type(value) })
		return
	end

	value = line_lower:match("^status[%.%s]+name%s+does%s+not%s+include%s+(.+)$")
	if value then
		add_filter(plan, { type = "status_name_includes", value = trim(value), negate = true })
		return
	end

	value = line_lower:match("^status[%.%s]+name%s+includes%s+(.+)$")
	if value then
		add_filter(plan, { type = "status_name_includes", value = trim(value), negate = false })
		return
	end

	for _, field in ipairs({
		"description",
		"tag",
		"tags",
		"path",
		"root",
		"folder",
		"filename",
		"heading",
		"id",
		"recurrence",
		"status.name",
		"status.type",
	}) do
		local field_pattern = field:gsub("%.", "%%.")
		value = line:match("^" .. field_pattern .. "%s+does%s+not%s+include%s+(.+)$")
		if value then
			add_filter(plan, {
				type = "includes",
				field = field == "tags" and "tag" or field,
				value = trim(value),
				negate = true,
			})
			return
		end

		value = line:match("^" .. field_pattern .. "%s+includes%s+(.+)$")
		if value then
			add_filter(plan, {
				type = "includes",
				field = field == "tags" and "tag" or field,
				value = trim(value),
				negate = false,
			})
			return
		end

		value = line:match("^" .. field_pattern .. "%s+regex%s+does%s+not%s+match%s+(.+)$")
		if value then
			local regex, err = parse_regex_expr(value)
			if not regex then
				add_error(plan, line_number, original_line, "Invalid regex: " .. tostring(err))
			else
				add_filter(plan, {
					type = "regex",
					field = field == "tags" and "tag" or field,
					regex = regex,
					negate = true,
				})
			end
			return
		end

		value = line:match("^" .. field_pattern .. "%s+regex%s+matches%s+(.+)$")
		if value then
			local regex, err = parse_regex_expr(value)
			if not regex then
				add_error(plan, line_number, original_line, "Invalid regex: " .. tostring(err))
			else
				add_filter(plan, {
					type = "regex",
					field = field == "tags" and "tag" or field,
					regex = regex,
					negate = false,
				})
			end
			return
		end
	end

	value = line_lower:match("^priority%s+is%s+above%s+(.+)$")
	if value then
		local priority = normalize_priority(value)
		if not priority then
			add_error(plan, line_number, original_line, "Invalid priority: " .. trim(value))
		else
			table.insert(plan.filters, { type = "priority", op = "above", value = priority })
		end
		return
	end

	value = line_lower:match("^priority%s+is%s+below%s+(.+)$")
	if value then
		local priority = normalize_priority(value)
		if not priority then
			add_error(plan, line_number, original_line, "Invalid priority: " .. trim(value))
		else
			table.insert(plan.filters, { type = "priority", op = "below", value = priority })
		end
		return
	end

	value = line_lower:match("^priority%s+is%s+(.+)$")
	if value then
		local priority = normalize_priority(value)
		if not priority then
			add_error(plan, line_number, original_line, "Invalid priority: " .. trim(value))
		else
			table.insert(plan.filters, { type = "priority", op = "is", value = priority })
		end
		return
	end

	local field = line_lower:match("^has%s+(.+)%s+date$")
	if field then
		add_date_exists_filter(plan, line_number, original_line, field, true)
		return
	end

	field = line_lower:match("^no%s+(.+)%s+date$")
	if field then
		add_date_exists_filter(plan, line_number, original_line, field, false)
		return
	end

	field, value = line_lower:match("^(%w+)%s+on%s+or%s+before%s+(.+)$")
	if field and value then
		add_date_filter(plan, line_number, original_line, field, "on_or_before", value, opts)
		return
	end

	field, value = line_lower:match("^(%w+)%s+on%s+or%s+after%s+(.+)$")
	if field and value then
		add_date_filter(plan, line_number, original_line, field, "on_or_after", value, opts)
		return
	end

	field, value = line_lower:match("^(%w+)%s+before%s+(.+)$")
	if field and value then
		add_date_filter(plan, line_number, original_line, field, "before", value, opts)
		return
	end

	field, value = line_lower:match("^(%w+)%s+after%s+(.+)$")
	if field and value then
		add_date_filter(plan, line_number, original_line, field, "after", value, opts)
		return
	end

	field, value = line_lower:match("^(%w+)%s+on%s+(.+)$")
	if field and value then
		add_date_filter(plan, line_number, original_line, field, "on", value, opts)
		return
	end

	if line_lower == "is recurring" then
		table.insert(plan.filters, { type = "recurring", value = true })
		return
	elseif line_lower == "is not recurring" then
		table.insert(plan.filters, { type = "recurring", value = false })
		return
	elseif line_lower == "has id" then
		table.insert(plan.filters, { type = "id_exists", exists = true })
		return
	elseif line_lower == "no id" then
		table.insert(plan.filters, { type = "id_exists", exists = false })
		return
	elseif line_lower == "has depends on" then
		table.insert(plan.filters, { type = "depends_on_exists", exists = true })
		return
	elseif line_lower == "no depends on" then
		table.insert(plan.filters, { type = "depends_on_exists", exists = false })
		return
	elseif line_lower == "is blocked" then
		table.insert(plan.filters, { type = "dependency_state", state = "blocked", value = true })
		return
	elseif line_lower == "is not blocked" then
		table.insert(plan.filters, { type = "dependency_state", state = "blocked", value = false })
		return
	elseif line_lower == "is blocking" then
		table.insert(plan.filters, { type = "dependency_state", state = "blocking", value = true })
		return
	elseif line_lower == "is not blocking" then
		table.insert(plan.filters, { type = "dependency_state", state = "blocking", value = false })
		return
	end

	local sort_field = line_lower:match("^sort%s+by%s+(.+)$")
	if sort_field then
		local reverse = false
		sort_field = trim(sort_field)
		local without_reverse = sort_field:match("^(.-)%s+reverse$")
		if without_reverse then
			sort_field = trim(without_reverse)
			reverse = true
		end
		if not SORT_FIELDS[sort_field] then
			add_error(plan, line_number, original_line, "Unsupported sort field: " .. sort_field)
		else
			table.insert(plan.sorts, { field = sort_field, reverse = reverse })
		end
		return
	end

	local group_field = line_lower:match("^group%s+by%s+(.+)$")
	if group_field then
		group_field = trim(group_field)
		if not GROUP_FIELDS[group_field] then
			add_error(plan, line_number, original_line, "Unsupported group field: " .. group_field)
		else
			table.insert(plan.group_by, group_field)
		end
		return
	end

	value = line_lower:match("^limit%s+groups%s+to%s+(%d+)")
		or line_lower:match("^limit%s+groups%s+(%d+)")
	if value then
		plan.group_limit = tonumber(value)
		return
	end

	value = line_lower:match("^limit%s+to%s+(%d+)")
		or line_lower:match("^limit%s+(%d+)")
	if value then
		plan.limit = tonumber(value)
		return
	end

	add_error(plan, line_number, original_line, "Unsupported query instruction")
end

function M.parse(query, opts)
	opts = opts or {}
	local source = tostring(query or "")
	local query_file = query_file_context(opts)
	local expanded, placeholder_errors = expand_placeholders(source, opts, query_file)
	local plan = {
		raw = query or "",
		expanded = expanded,
		query_file = query_file,
		queryFile = query_file,
		filters = {},
		sorts = {},
		group_by = {},
		limit = nil,
		errors = {},
		warnings = {},
	}

	if #placeholder_errors > 0 then
		for _, err in ipairs(placeholder_errors) do
			add_error(plan, 0, source, err)
		end
		return plan
	end

	local line_number = 0
	for line in (expanded .. "\n"):gmatch("(.-)\n") do
		line_number = line_number + 1
		parse_line(plan, line_number, line, opts)
	end

	return plan
end

function M.compose(query, opts)
	opts = opts or {}
	local query_file_defaults = ""
	if opts.apply_query_file_defaults ~= false and opts.applyQueryFileDefaults ~= false then
		query_file_defaults = require("obsidian-tasks.query_file_defaults").source(opts)
	end

	local local_source = join_sources({
		query_file_defaults,
		query or "",
	})
	local local_plan = M.parse(local_source, opts)
	local global_source = ""
	if not local_plan.ignore_global_query then
		global_source = strip_ignore_global_query(global_query_source(opts))
	end

	return {
		source = join_sources({
			global_source,
			local_source,
		}),
		original_source = query or "",
		global_query = global_source,
		query_file_defaults = query_file_defaults,
		local_source = local_source,
		ignore_global_query = local_plan.ignore_global_query,
		applied_global_query = trim(global_source) ~= "",
		applied_query_file_defaults = trim(query_file_defaults) ~= "",
		preflight_errors = local_plan.errors,
	}
end

local function task_done(task, opts)
	return status.is_complete_symbol(task.status_symbol or task.status, opts)
end

local function task_status_symbol(task)
	if task.status_symbol then
		return task.status_symbol
	end
	return (task.status or ""):match("^%[(.)%]$") or ""
end

local function field_text(task, field)
	if field == "description" then
		return task.description or task.text or ""
	elseif field == "path" then
		return task.file_path or ""
	elseif field == "root" then
		return task.file and task.file.root or "/"
	elseif field == "folder" then
		return task.file and task.file.folder or ""
	elseif field == "filename" then
		if task.file and task.file.filename_without_extension then
			return task.file.filename_without_extension
		end
		local filename = (task.file_path or ""):match("([^/]+)$") or ""
		return filename:gsub("%.[^%.]+$", "")
	elseif field == "heading" then
		return task.heading or ""
	elseif field == "id" then
		return task.id or ""
	elseif field == "recurrence" then
		return task.recurrence_rule or ""
	elseif field == "status.name" then
		return status.get(task_status_symbol(task)).name
	elseif field == "status.type" then
		return status.type(task_status_symbol(task))
	end
	return ""
end

local function tag_matches(task, needle)
	needle = lower(needle)
	for _, tag in ipairs(task.tags or {}) do
		if tag:lower():find(needle, 1, true) then
			return true
		end
	end
	return false
end

local function includes_matches(task, filter)
	local matched
	if filter.field == "tag" then
		matched = tag_matches(task, filter.value)
	else
		matched = field_text(task, filter.field):lower():find(lower(filter.value), 1, true) ~= nil
	end

	if filter.negate then
		return not matched
	end
	return matched
end

local function regex_matches(task, filter)
	local function matches_text(text)
		return filter.regex.compiled:match_str(text or "") ~= nil
	end

	local matched
	if filter.field == "tag" then
		matched = false
		for _, tag in ipairs(task.tags or {}) do
			if matches_text(tag) then
				matched = true
				break
			end
		end
	else
		matched = matches_text(field_text(task, filter.field))
	end

	if filter.negate then
		return not matched
	end
	return matched
end

local function priority_order(priority)
	return sort.PRIORITY_ORDER[priority or "normal"] or sort.PRIORITY_ORDER.normal
end

local boolean_node_matches

local function filter_matches(task, filter, context)
	context = context or {}
	if filter.type == "done" then
		return task_done(task, context.status_config) == filter.value
	elseif filter.type == "status" then
		local expected = status.resolve_symbol(filter.value, context.status_config) or normalize_status(filter.value)
		local matches = task_status_symbol(task) == expected
		if filter.op == "is_not" then
			return not matches
		end
		return matches
	elseif filter.type == "status_type" then
		local matches = status.type(task_status_symbol(task), context.status_config) == filter.value
		if filter.op == "is_not" then
			return not matches
		end
		return matches
	elseif filter.type == "status_name_includes" then
		local entry = status.get(task_status_symbol(task), context.status_config)
		local matches = entry.name:lower():find(lower(filter.value), 1, true) ~= nil
		if filter.negate then
			return not matches
		end
		return matches
	elseif filter.type == "includes" then
		return includes_matches(task, filter)
	elseif filter.type == "regex" then
		return regex_matches(task, filter)
	elseif filter.type == "function" then
		local ok, result = pcall(filter.fn, task, context.query or {})
		return ok and result == true
	elseif filter.type == "boolean" then
		return boolean_node_matches(filter.node, task, context)
	elseif filter.type == "priority" then
		local task_priority = priority_order(task.priority)
		local expected = priority_order(filter.value)
		if filter.op == "is" then
			return task_priority == expected
		elseif filter.op == "above" then
			return task_priority < expected
		elseif filter.op == "below" then
			return task_priority > expected
		end
	elseif filter.type == "date_exists" then
		local has_date = date.is_valid(date.get_task_date(task, filter.field))
		return has_date == filter.exists
	elseif filter.type == "date_compare" then
		return date.matches(date.get_task_date(task, filter.field), filter.op, filter.value)
	elseif filter.type == "recurring" then
		return (task.is_recurring == true) == filter.value
	elseif filter.type == "id_exists" then
		return ((task.id or "") ~= "") == filter.exists
	elseif filter.type == "depends_on_exists" then
		return (#(task.depends_on or {}) > 0) == filter.exists
	elseif filter.type == "dependency_state" then
		local matched
		if filter.state == "blocked" then
			matched = dependencies.is_blocked(task, context.tasks, context.status_config)
		else
			matched = dependencies.is_blocking(task, context.tasks, context.status_config)
		end
		return matched == filter.value
	end

	return true
end

function boolean_node_matches(node, task, context)
	if not node then
		return true
	end

	if node.type == "filter" then
		return filter_matches(task, node.filter, context)
	elseif node.type == "and" then
		return boolean_node_matches(node.left, task, context) and boolean_node_matches(node.right, task, context)
	elseif node.type == "or" then
		return boolean_node_matches(node.left, task, context) or boolean_node_matches(node.right, task, context)
	elseif node.type == "not" then
		return not boolean_node_matches(node.child, task, context)
	end

	return true
end

function M.matches(task, plan, context)
	local group_matched = true
	local group_has_filter = false
	local saw_or = false

	for _, filter in ipairs(plan.filters or {}) do
		if filter.type == "or" then
			if group_has_filter and group_matched then
				return true
			end
			saw_or = true
			group_matched = true
			group_has_filter = false
		else
			group_has_filter = true
			if not filter_matches(task, filter, context) then
				group_matched = false
			end
		end
	end

	if saw_or then
		return group_has_filter and group_matched
	end
	return group_matched
end

function M.filter_tasks(tasks, plan)
	local filtered = {}
	local context = {
		tasks = tasks or {},
		status_config = require("obsidian-tasks").config or {},
		query_file = plan and plan.query_file or nil,
		queryFile = plan and plan.query_file or nil,
		query = {
			all_tasks = tasks or {},
			allTasks = tasks or {},
			file = plan and plan.query_file or nil,
			query_file = plan and plan.query_file or nil,
			queryFile = plan and plan.query_file or nil,
		},
	}
	for _, task in ipairs(tasks or {}) do
		if M.matches(task, plan, context) then
			table.insert(filtered, task)
		end
	end
	return filtered
end

return M
