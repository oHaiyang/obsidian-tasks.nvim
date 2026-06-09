local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function count_filters(filters)
	local count = 0
	for _, filter in ipairs(filters or {}) do
		if filter.type ~= "or" then
			count = count + 1
		end
	end
	return count
end

local function date_value_label(value)
	if type(value) == "table" and value.start and value["end"] then
		if value.start == value["end"] then
			return value.start
		end
		return value.start .. ".." .. value["end"]
	end
	return tostring(value or "")
end

local function filter_label(filter)
	if not filter then
		return "unknown filter"
	elseif filter.type == "or" then
		return "OR group separator"
	elseif filter.type == "done" then
		return filter.value and "done" or "not done"
	elseif filter.type == "includes" then
		return string.format("%s %sincludes %s", filter.field or "field", filter.negate and "does not " or "", filter.value or "")
	elseif filter.type == "regex" then
		return string.format("%s regex %s /%s/%s", filter.field or "field", filter.negate and "does not match" or "matches", filter.regex and filter.regex.pattern or "", filter.regex and filter.regex.flags or "")
	elseif filter.type == "date_compare" then
		return string.format("%s %s %s", filter.field or "date", filter.op or "matches", date_value_label(filter.value))
	elseif filter.type == "date_exists" then
		return string.format("%s %s date", filter.exists and "has" or "no", filter.field or "")
	elseif filter.type == "priority" then
		return string.format("priority %s %s", filter.op or "is", filter.value or "")
	elseif filter.type == "status" then
		return string.format("status %s %s", filter.op or "is", filter.value or "")
	elseif filter.type == "status_type" then
		return string.format("status.type %s %s", filter.op or "is", filter.value or "")
	elseif filter.type == "boolean" then
		return "Boolean expression"
	elseif filter.type == "function" then
		return "Lua function: " .. trim(filter.expr)
	end
	return filter.type or "unknown filter"
end

local function append_list(lines, title, values, formatter)
	if not values or #values == 0 then
		table.insert(lines, "- " .. title .. ": none")
		return
	end
	table.insert(lines, "- " .. title .. ":")
	for _, value in ipairs(values) do
		table.insert(lines, "  - " .. formatter(value))
	end
end

local function composition_lines(composition)
	local lines = {}
	if not composition then
		return lines
	end
	table.insert(lines, "- global query: " .. (composition.applied_global_query and "applied" or "not applied"))
	table.insert(lines, "- query file defaults: " .. (composition.applied_query_file_defaults and "applied" or "not applied"))
	if composition.ignore_global_query then
		table.insert(lines, "- ignore global query: true")
	end
	return lines
end

function M.summary(plan)
	plan = plan or {}
	return string.format(
		"Explain: %d filter(s), %d sort(s), %d group(s)",
		count_filters(plan.filters),
		#(plan.sorts or {}),
		#(plan.group_by or {})
	)
end

function M.lines(plan, opts)
	plan = plan or {}
	opts = opts or {}
	local lines = {
		"Explain:",
	}

	for _, line in ipairs(composition_lines(plan.composition or opts.composition)) do
		table.insert(lines, line)
	end

	append_list(lines, "filters", plan.filters, filter_label)
	append_list(lines, "sorts", plan.sorts, function(sort)
		return string.format("%s%s", sort.field or "unknown", sort.reverse and " reverse" or "")
	end)
	append_list(lines, "groups", plan.group_by, tostring)

	if plan.limit then
		table.insert(lines, "- limit: " .. tostring(plan.limit))
	end
	if plan.group_limit then
		table.insert(lines, "- group limit: " .. tostring(plan.group_limit))
	end
	if plan.layout and plan.layout.short_mode ~= nil then
		table.insert(lines, "- mode: " .. (plan.layout.short_mode and "short" or "full"))
	end
	if plan.layout_statements and #plan.layout_statements > 0 then
		table.insert(lines, "- layout statements: " .. tostring(#plan.layout_statements))
	end

	table.insert(lines, "")
	return lines
end

function M.error_lines(errors, opts)
	opts = opts or {}
	local lines = {
		"Query errors:",
	}
	for _, line in ipairs(composition_lines(opts.composition)) do
		table.insert(lines, line)
	end
	table.insert(lines, "")

	if not errors or #errors == 0 then
		table.insert(lines, "- Unknown query error")
		return lines
	end

	for _, err in ipairs(errors) do
		table.insert(lines, string.format("- line %d: %s", err.line_number or 0, err.message or "Unknown error"))
		if trim(err.line) ~= "" then
			table.insert(lines, "  instruction: " .. trim(err.line))
		end
	end
	return lines
end

return M
