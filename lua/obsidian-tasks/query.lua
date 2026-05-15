local M = {}

local date = require("obsidian-tasks.date")
local sort = require("obsidian-tasks.sort")

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

local function add_error(plan, line_number, line, message)
	table.insert(plan.errors, {
		line_number = line_number,
		line = line,
		message = message,
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

	table.insert(plan.filters, {
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

	table.insert(plan.filters, {
		type = "date_exists",
		field = field,
		exists = exists,
	})
end

local function parse_line(plan, line_number, line, opts)
	local original_line = line
	line = trim(line)
	if line == "" or line:match("^#") then
		return
	end

	local line_lower = line:lower()

	if line_lower == "not done" then
		table.insert(plan.filters, { type = "done", value = false })
		return
	elseif line_lower == "done" then
		table.insert(plan.filters, { type = "done", value = true })
		return
	end

	local value = line:match("^status%s+is%s+not%s+(.+)$")
	if value then
		table.insert(plan.filters, { type = "status", op = "is_not", value = normalize_status(value) })
		return
	end

	value = line:match("^status%s+is%s+(.+)$")
	if value then
		table.insert(plan.filters, { type = "status", op = "is", value = normalize_status(value) })
		return
	end

	for _, field in ipairs({ "description", "tag", "tags", "path", "filename", "heading" }) do
		value = line:match("^" .. field .. "%s+does%s+not%s+include%s+(.+)$")
		if value then
			table.insert(plan.filters, {
				type = "includes",
				field = field == "tags" and "tag" or field,
				value = trim(value),
				negate = true,
			})
			return
		end

		value = line:match("^" .. field .. "%s+includes%s+(.+)$")
		if value then
			table.insert(plan.filters, {
				type = "includes",
				field = field == "tags" and "tag" or field,
				value = trim(value),
				negate = false,
			})
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

	value = line_lower:match("^limit%s+(%d+)$")
	if value then
		plan.limit = tonumber(value)
		return
	end

	add_error(plan, line_number, original_line, "Unsupported query instruction")
end

function M.parse(query, opts)
	opts = opts or {}
	local plan = {
		raw = query or "",
		filters = {},
		sorts = {},
		group_by = {},
		limit = nil,
		errors = {},
		warnings = {},
	}

	local source = tostring(query or "")
	local line_number = 0
	for line in (source .. "\n"):gmatch("(.-)\n") do
		line_number = line_number + 1
		parse_line(plan, line_number, line, opts)
	end

	return plan
end

local function task_done(task)
	return task.status_symbol ~= nil and task.status_symbol ~= " "
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
	elseif field == "filename" then
		if task.file and task.file.filename_without_extension then
			return task.file.filename_without_extension
		end
		local filename = (task.file_path or ""):match("([^/]+)$") or ""
		return filename:gsub("%.[^%.]+$", "")
	elseif field == "heading" then
		return task.heading or ""
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

local function priority_order(priority)
	return sort.PRIORITY_ORDER[priority or "normal"] or sort.PRIORITY_ORDER.normal
end

local function filter_matches(task, filter)
	if filter.type == "done" then
		return task_done(task) == filter.value
	elseif filter.type == "status" then
		local matches = task_status_symbol(task) == filter.value
		if filter.op == "is_not" then
			return not matches
		end
		return matches
	elseif filter.type == "includes" then
		return includes_matches(task, filter)
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
	end

	return true
end

function M.matches(task, plan)
	for _, filter in ipairs(plan.filters or {}) do
		if not filter_matches(task, filter) then
			return false
		end
	end
	return true
end

function M.filter_tasks(tasks, plan)
	local filtered = {}
	for _, task in ipairs(tasks or {}) do
		if M.matches(task, plan) then
			table.insert(filtered, task)
		end
	end
	return filtered
end

return M
