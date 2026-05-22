local M = {}

local urgency = require("obsidian-tasks.urgency")

M.PRIORITY_EMOJIS = {
	["🔺"] = "highest",
	["⏫"] = "high",
	["🔼"] = "medium",
	["🔽"] = "low",
	["⏬"] = "lowest",
	["⏬️"] = "lowest",
}

M.PRIORITY_SYMBOLS = {
	highest = "🔺",
	high = "⏫",
	medium = "🔼",
	low = "🔽",
	lowest = "⏬",
}

M.DATE_SYMBOLS = {
	created = { "➕" },
	start = { "🛫" },
	scheduled = { "⏳", "⌛" },
	due = { "📅", "📆", "🗓" },
	cancelled = { "❌" },
	done = { "✅" },
}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
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

local function normalize_status_symbol(status)
	if status == nil or status == "" then
		return " "
	end
	if #status == 3 and status:sub(1, 1) == "[" and status:sub(3, 3) == "]" then
		return status:sub(2, 2)
	end
	return status
end

local function status_text(status_symbol)
	return "[" .. normalize_status_symbol(status_symbol) .. "]"
end

local function parse_task_prefix(line)
	local indentation, list_marker, status_symbol, body = line:match("^([%s\t>]*)([-*+])%s+%[(.)%]%s*(.*)$")
	if indentation then
		return indentation, list_marker, status_symbol, body
	end

	indentation, list_marker, status_symbol, body = line:match("^([%s\t>]*)(%d+[%.%)])%s+%[(.)%]%s*(.*)$")
	if indentation then
		return indentation, list_marker, status_symbol, body
	end

	return nil
end

local function extract_trailing_tag(state)
	local before, tag = state.line:match("^(.-)%s*(#[^%s%!%@#%$%%%^%&%*%(%)%,%.%?%\":%{%}%|%<%>]+)%s*$")
	if tag then
		state.line = trim(before)
		table.insert(state.trailing_tags, 1, tag)
		return true
	end
	return false
end

local function extract_block_link(state)
	local before, block_link = state.line:match("^(.-)%s+(%^[%w%-]+)%s*$")
	if block_link then
		state.line = trim(before)
		state.task.block_link = block_link
		return true
	end
	return false
end

local function extract_priority(state)
	for symbol, priority in pairs(M.PRIORITY_EMOJIS) do
		local before = state.line:match("^(.-)%s*" .. symbol .. "%s*$")
		if before then
			state.line = trim(before)
			state.task.priority = priority
			state.task.priority_symbol = symbol
			return true
		end
	end
	return false
end

local function extract_date(state)
	for field, symbols in pairs(M.DATE_SYMBOLS) do
		for _, symbol in ipairs(symbols) do
			local before, value = state.line:match("^(.-)%s*" .. symbol .. "%s*(%d%d%d%d%-%d%d%-%d%d)%s*$")
			if before then
				state.line = trim(before)
				state.task.dates[field] = value
				state.task[field .. "_date"] = value
				return true
			end
		end
	end
	return false
end

local function extract_recurrence(state)
	local before, rule = state.line:match("^(.-)%s*🔁%s*([%w%s,!]+)%s*$")
	if before then
		state.line = trim(before)
		state.task.recurrence_rule = trim(rule)
		state.task.is_recurring = state.task.recurrence_rule ~= ""
		return true
	end
	return false
end

local function extract_on_completion(state)
	local before, value = state.line:match("^(.-)%s*🏁%s*([%a]+)%s*$")
	if before then
		state.line = trim(before)
		state.task.on_completion = trim(value):lower()
		return true
	end
	return false
end

local function extract_id(state)
	local before, value = state.line:match("^(.-)%s*🆔%s*([%w_%-]+)%s*$")
	if before then
		state.line = trim(before)
		state.task.id = value
		return true
	end
	return false
end

local function extract_depends_on(state)
	local before, value = state.line:match("^(.-)%s*⛔%s*([%w_%-,%s]+)%s*$")
	if before then
		state.line = trim(before)
		state.task.depends_on = split_csv(value)
		state.task.dependsOn = state.task.depends_on
		return true
	end
	return false
end

local function extract_tags(description)
	local tags = {}
	for tag in (description or ""):gmatch("(^#[^%s%!%@#%$%%%^%&%*%(%)%,%.%?%\":%{%}%|%<%>]+)") do
		table.insert(tags, trim(tag))
	end
	for tag in (description or ""):gmatch("(%s#[^%s%!%@#%$%%%^%&%*%(%)%,%.%?%\":%{%}%|%<%>]+)") do
		table.insert(tags, trim(tag))
	end
	return tags
end

local function enrich_file_fields(task)
	local path = task.file_path or ""
	local filename = basename(path)
	task.file = {
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

function M.extract_priority(task_text)
	for symbol, priority in pairs(M.PRIORITY_EMOJIS) do
		if (task_text or ""):find(symbol, 1, true) then
			return priority
		end
	end
	return "normal"
end

function M.parse_line(opts)
	opts = opts or {}
	local line = opts.line or ""
	local indentation, list_marker, status_symbol, body = parse_task_prefix(line)
	if not indentation then
		return nil
	end

	local global_filter = opts.global_filter or opts.globalFilter or ""
	if global_filter ~= "" and not body:find(global_filter, 1, true) then
		return nil
	end

	local task = {
		indentation = indentation,
		list_marker = list_marker,
		listMarker = list_marker,
		status_symbol = status_symbol,
		status = status_text(status_symbol),
		body = body,
		display_text = body,
		original_markdown = line,
		originalMarkdown = line,
		file_path = opts.file_path,
		line_number = opts.line_number,
		heading = opts.heading,
		priority = "normal",
		priority_symbol = "",
		dates = {},
		tags = {},
		recurrence_rule = "",
		is_recurring = false,
		on_completion = "",
		id = "",
		depends_on = {},
		dependsOn = {},
		block_link = "",
	}

	local state = {
		line = trim(body),
		task = task,
		trailing_tags = {},
	}

	extract_block_link(state)

	local max_runs = 30
	for _ = 1, max_runs do
		local matched = extract_priority(state)
			or extract_date(state)
			or extract_recurrence(state)
			or extract_on_completion(state)
			or extract_id(state)
			or extract_depends_on(state)
			or extract_trailing_tag(state)
		if not matched then
			break
		end
	end

	local description = trim(state.line)
	if #state.trailing_tags > 0 then
		description = trim(description .. " " .. table.concat(state.trailing_tags, " "))
	end

	task.text = description
	task.description = description
	task.tags = extract_tags(description)
	task.due_date = task.dates.due
	task.created_date = task.dates.created
	task.start_date = task.dates.start
	task.scheduled_date = task.dates.scheduled
	task.cancelled_date = task.dates.cancelled
	task.done_date = task.dates.done

	enrich_file_fields(task)
	urgency.enrich(task, opts)

	return task
end

function M.serialize(task)
	local body = task.body or task.display_text or task.text or ""
	local prefix = string.format("%s%s [%s]", task.indentation or "", task.list_marker or "-", normalize_status_symbol(task.status_symbol or task.status))
	if body == "" then
		return prefix
	end
	return prefix .. " " .. body
end

function M.with_status(task, status)
	local updated = {}
	for key, value in pairs(task) do
		updated[key] = value
	end
	updated.status_symbol = normalize_status_symbol(status)
	updated.status = status_text(updated.status_symbol)
	return updated
end

function M.toggle_status(task)
	local current = normalize_status_symbol(task.status_symbol or task.status)
	if current == " " then
		return M.with_status(task, "x")
	end
	return M.with_status(task, " ")
end

function M.status_text(status)
	return status_text(status)
end

return M
