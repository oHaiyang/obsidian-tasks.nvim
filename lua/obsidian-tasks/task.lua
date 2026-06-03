local M = {}

local links = require("obsidian-tasks.links")
local source = require("obsidian-tasks.source")
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

M.DATAVIEW_DATE_KEYS = {
	created = "created",
	start = "start",
	scheduled = "scheduled",
	due = "due",
	done = "completion",
	cancelled = "cancelled",
}

M.DATAVIEW_FIELD_KEYS = {
	priority = "priority",
	recurrence = "repeat",
	on_completion = "onCompletion",
	id = "id",
	depends_on = "dependsOn",
}

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

local function normalize_task_format(value)
	value = tostring(value or "tasks"):lower()
	if value == "dataview" then
		return "dataview"
	end
	return "tasks"
end

function M.task_format(opts)
	opts = opts or {}
	return normalize_task_format(opts.task_format or opts.taskFormat or get_config().task_format or get_config().taskFormat)
end

function M.is_dataview_format(opts)
	return M.task_format(opts) == "dataview"
end

local function clean_body(value)
	value = trim(value)
	value = value:gsub("%s%s%s+", "  ")
	return trim(value)
end

local function dataview_square_pattern(key)
	return "%s*%[%s*" .. key .. "::%s*[^%]]+%s*%]%s*,?"
end

local function dataview_paren_pattern(key)
	return "%s*%(%s*" .. key .. "::%s*[^%)]+%s*%)%s*,?"
end

local function dataview_value(line, key)
	local value = (line or ""):match("%[%s*" .. key .. "::%s*([^%]]+)%s*%]")
		or (line or ""):match("%(%s*" .. key .. "::%s*([^%)]+)%s*%)")
	if value then
		return trim(value):gsub("%s*,%s*$", "")
	end
	return nil
end

function M.dataview_field_value(line, key)
	return dataview_value(line, key)
end

function M.dataview_inline_field(key, value)
	return string.format("[%s:: %s]", key, value)
end

function M.remove_dataview_field(body, key)
	body = (body or ""):gsub(dataview_square_pattern(key), " ")
	body = body:gsub(dataview_paren_pattern(key), " ")
	return clean_body(body)
end

function M.set_dataview_field(body, key, value)
	value = trim(value)
	if value == "" then
		return M.remove_dataview_field(body, key)
	end

	local replacement = "  " .. M.dataview_inline_field(key, value)
	local updated, count = (body or ""):gsub(dataview_square_pattern(key), replacement, 1)
	if count == 0 then
		updated, count = (body or ""):gsub(dataview_paren_pattern(key), replacement, 1)
	end
	if count > 0 then
		return clean_body(updated)
	end

	local before, block_link = (body or ""):match("^(.-)%s+(%^[%w%-]+)%s*$")
	if block_link then
		return clean_body(trim(before) .. replacement .. " " .. block_link)
	end
	return clean_body((body or "") .. replacement)
end

function M.set_dataview_date(body, field, value)
	local key = M.DATAVIEW_DATE_KEYS[field]
	if not key then
		return clean_body(body)
	end
	return M.set_dataview_field(body, key, value)
end

function M.set_dataview_metadata(body, field, value)
	local key = M.DATAVIEW_FIELD_KEYS[field] or M.DATAVIEW_DATE_KEYS[field]
	if not key then
		return clean_body(body)
	end
	return M.set_dataview_field(body, key, value)
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

local function extract_dataview_metadata(state)
	state.task.dataview_fields = {}
	for field, key in pairs(M.DATAVIEW_DATE_KEYS) do
		local value = dataview_value(state.line, key)
		if value and value:match("^%d%d%d%d%-%d%d%-%d%d$") then
			state.task.dataview_fields[key] = value
			state.task.dates[field] = value
			state.task[field .. "_date"] = value
		end
	end

	local priority = dataview_value(state.line, M.DATAVIEW_FIELD_KEYS.priority)
	if priority then
		priority = trim(priority):lower()
		if priority ~= "" and priority ~= "normal" and priority ~= "none" then
			state.task.priority = priority
		end
		state.task.dataview_fields.priority = priority
	end

	local recurrence = dataview_value(state.line, M.DATAVIEW_FIELD_KEYS.recurrence)
	if recurrence then
		state.task.recurrence_rule = trim(recurrence)
		state.task.is_recurring = state.task.recurrence_rule ~= ""
		state.task.dataview_fields["repeat"] = state.task.recurrence_rule
	end

	local on_completion = dataview_value(state.line, M.DATAVIEW_FIELD_KEYS.on_completion)
	if on_completion then
		state.task.on_completion = trim(on_completion):lower()
		state.task.dataview_fields.onCompletion = state.task.on_completion
	end

	local id = dataview_value(state.line, M.DATAVIEW_FIELD_KEYS.id)
	if id then
		state.task.id = trim(id)
		state.task.dataview_fields.id = state.task.id
	end

	local depends_on = dataview_value(state.line, M.DATAVIEW_FIELD_KEYS.depends_on)
	if depends_on then
		state.task.depends_on = split_csv(depends_on)
		state.task.dependsOn = state.task.depends_on
		state.task.dataview_fields.dependsOn = table.concat(state.task.depends_on, ", ")
	end

	for _, key in pairs(M.DATAVIEW_DATE_KEYS) do
		state.line = M.remove_dataview_field(state.line, key)
	end
	for _, key in pairs(M.DATAVIEW_FIELD_KEYS) do
		state.line = M.remove_dataview_field(state.line, key)
	end
	return true
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

local function enrich_file_fields(task, opts)
	opts = opts or {}
	local path = task.file_path or ""
	local filename = basename(path)
	local frontmatter = opts.frontmatter or opts.properties or {}
	task.file = {
		path = path,
		path_without_extension = without_extension(path),
		pathWithoutExtension = without_extension(path),
		root = rootname(path),
		folder = dirname(path),
		filename = filename,
		filename_without_extension = without_extension(filename),
		filenameWithoutExtension = without_extension(filename),
		frontmatter = frontmatter,
		properties = frontmatter,
		tags = opts.file_tags or opts.tags or {},
		aliases = opts.file_aliases or opts.aliases or {},
		cssclasses = opts.file_cssclasses or opts.cssclasses or {},
		classes = opts.file_cssclasses or opts.cssclasses or {},
	}
	task.frontmatter = frontmatter
	task.properties = frontmatter
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
		links = {},
		outlinks = {},
		recurrence_rule = "",
		is_recurring = false,
		on_completion = "",
		id = "",
		depends_on = {},
		dependsOn = {},
		block_link = "",
		task_format = M.task_format(opts),
		taskFormat = M.task_format(opts),
	}

	local state = {
		line = trim(body),
		task = task,
		trailing_tags = {},
	}

	extract_block_link(state)

	if task.task_format == "dataview" then
		extract_dataview_metadata(state)
		local max_runs = 30
		for _ = 1, max_runs do
			if not extract_trailing_tag(state) then
				break
			end
		end
	else
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
	end

	local description = trim(state.line)
	if #state.trailing_tags > 0 then
		description = trim(description .. " " .. table.concat(state.trailing_tags, " "))
	end

	task.text = description
	task.description = description
	task.tags = extract_tags(description)
	task.links = links.extract(line)
	task.outlinks = task.links
	task.due_date = task.dates.due
	task.created_date = task.dates.created
	task.start_date = task.dates.start
	task.scheduled_date = task.dates.scheduled
	task.cancelled_date = task.dates.cancelled
	task.done_date = task.dates.done

	enrich_file_fields(task, opts)
	urgency.enrich(task, opts)
	source.enrich(task)

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
