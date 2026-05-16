local M = {}

local date = require("obsidian-tasks.date")
local status = require("obsidian-tasks.status")
local task_model = require("obsidian-tasks.task")

local DATE_SYMBOLS = {
	created = "➕",
	start = "🛫",
	scheduled = "⏳",
	due = "📅",
	done = "✅",
	cancelled = "❌",
}

local MARKDOWN_SYMBOLS = {
	{ symbol = "➕", field = "created" },
	{ symbol = "🛫", field = "start" },
	{ symbol = "⏳", field = "scheduled" },
	{ symbol = "📅", field = "due" },
	{ symbol = "✅", field = "done" },
	{ symbol = "❌", field = "cancelled" },
	{ symbol = "🔁", field = "recurrence" },
	{ symbol = "🏁", field = "on_completion" },
	{ symbol = "🆔", field = "id" },
	{ symbol = "⛔", field = "depends_on" },
}

local PRIORITY_SUGGESTIONS = {
	{ word = "highest", abbr = "highest 🔺", menu = "priority", filter_text = "highest" },
	{ word = "high", abbr = "high ⏫", menu = "priority", filter_text = "high" },
	{ word = "medium", abbr = "medium 🔼", menu = "priority", filter_text = "medium" },
	{ word = "none", abbr = "none", menu = "priority", filter_text = "none" },
	{ word = "low", abbr = "low 🔽", menu = "priority", filter_text = "low" },
	{ word = "lowest", abbr = "lowest ⏬", menu = "priority", filter_text = "lowest" },
}

local MARKDOWN_PRIORITY_SUGGESTIONS = {
	{ word = "🔺", abbr = "highest 🔺", menu = "priority", filter_text = "highest" },
	{ word = "⏫", abbr = "high ⏫", menu = "priority", filter_text = "high" },
	{ word = "🔼", abbr = "medium 🔼", menu = "priority", filter_text = "medium" },
	{ word = "🔽", abbr = "low 🔽", menu = "priority", filter_text = "low" },
	{ word = "⏬", abbr = "lowest ⏬", menu = "priority", filter_text = "lowest" },
}

local DATE_SUGGESTIONS = {
	{ expr = "today", word = "today", menu = "date" },
	{ expr = "tomorrow", word = "tomorrow", menu = "date" },
	{ expr = "yesterday", word = "yesterday", menu = "date" },
	{ expr = "+1", word = "+1", abbr = "+1 tomorrow", menu = "date" },
	{ expr = "+7", word = "+7", abbr = "+7 one week", menu = "date" },
	{ expr = "1 week", word = "1 week", menu = "date" },
	{ expr = "2 weeks", word = "2 weeks", menu = "date" },
	{ expr = "1 month", word = "1 month", menu = "date" },
	{ expr = "next week", word = "next week", menu = "date" },
	{ expr = "next month", word = "next month", menu = "date" },
}

local RECURRENCE_SUGGESTIONS = {
	{ word = "every day", menu = "recurrence", filter_text = "every day" },
	{ word = "every weekday", menu = "recurrence", filter_text = "every weekday" },
	{ word = "every week", menu = "recurrence", filter_text = "every week" },
	{ word = "every month", menu = "recurrence", filter_text = "every month" },
	{ word = "every year", menu = "recurrence", filter_text = "every year" },
	{ word = "every week when done", menu = "recurrence", filter_text = "every week when done" },
	{ word = "every month when done", menu = "recurrence", filter_text = "every month when done" },
}

local ON_COMPLETION_SUGGESTIONS = {
	{ word = "keep", menu = "on completion", filter_text = "keep" },
	{ word = "delete", menu = "on completion", filter_text = "delete" },
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

function M.config_bool(config, snake, camel, default)
	config = config or {}
	if config[snake] ~= nil then
		return config[snake] ~= false
	end
	if config[camel] ~= nil then
		return config[camel] ~= false
	end
	return default
end

function M.config_number(config, snake, camel, default)
	config = config or {}
	local value = config[snake]
	if value == nil then
		value = config[camel]
	end
	value = tonumber(value)
	if not value then
		return default
	end
	return value
end

function M.auto_suggest_enabled()
	return M.config_bool(get_config(), "auto_suggest_in_editor", "autoSuggestInEditor", true)
end

local function state_with_defaults(state)
	state = state or {}
	local config = get_config()
	state.vault_path = state.vault_path or config.vault_path
	state.today = state.today or config.today
	return state
end

local function clone_item(item)
	return {
		word = item.word,
		abbr = item.abbr or item.word,
		menu = item.menu,
		kind = item.kind,
		filter_text = item.filter_text,
	}
end

local function append_items(items, source)
	for _, item in ipairs(source or {}) do
		table.insert(items, clone_item(item))
	end
end

local function existing_ids(state)
	state = state_with_defaults(state)
	if state.cached_ids then
		return state.cached_ids
	end

	local config = get_config()
	local ids = {}
	local seen = {}
	if state.vault_path and state.vault_path ~= "" then
		local scanner = require("obsidian-tasks.scanner")
		for _, task in ipairs(scanner.scan_vault({
			vault_path = state.vault_path,
			global_filter = config.global_filter,
		})) do
			local id = trim(task.id)
			if id ~= "" and not seen[id] then
				table.insert(ids, id)
				seen[id] = true
			end
		end
	end
	table.sort(ids)
	state.cached_ids = ids
	return ids
end

local function generated_id(state)
	state = state_with_defaults(state)
	if state.generated_id then
		return state.generated_id
	end
	local stamp = (state.today or date.today()):gsub("%-", "")
	state.generated_id = "task-" .. stamp
	return state.generated_id
end

local function status_suggestions()
	local items = {}
	for _, entry in ipairs(status.registry(get_config())) do
		table.insert(items, {
			word = entry.name,
			abbr = string.format("[%s] %s", entry.symbol, entry.name),
			menu = entry.type,
			filter_text = entry.name,
		})
		if entry.symbol ~= " " then
			table.insert(items, {
				word = entry.symbol,
				abbr = "[" .. entry.symbol .. "]",
				menu = entry.name,
				filter_text = entry.symbol,
			})
		end
	end
	return items
end

local function date_suggestions(context, state)
	local items = {}
	for _, source in ipairs(DATE_SUGGESTIONS) do
		local item = clone_item(source)
		item.filter_text = source.word
		if context == "markdown" then
			local parsed = date.parse_date_expr(source.expr or source.word, { today = state_with_defaults(state).today })
			if parsed then
				item.word = parsed
				item.abbr = (source.abbr or source.word) .. " -> " .. parsed
			end
		end
		table.insert(items, item)
	end
	return items
end

local function id_suggestions(state)
	local items = {
		{ word = generated_id(state), menu = "new id", filter_text = generated_id(state) },
	}
	for _, id in ipairs(existing_ids(state)) do
		table.insert(items, { word = id, menu = "existing id", filter_text = id })
	end
	return items
end

local function depends_on_suggestions(state)
	local items = {}
	for _, id in ipairs(existing_ids(state)) do
		table.insert(items, { word = id, menu = "depends on", filter_text = id })
	end
	return items
end

local function field_suggestions(field, state, opts)
	opts = opts or {}
	local items = {}
	if field == "status" then
		append_items(items, status_suggestions())
	elseif field == "priority" then
		append_items(items, PRIORITY_SUGGESTIONS)
	elseif field == "markdown_priority" then
		append_items(items, MARKDOWN_PRIORITY_SUGGESTIONS)
	elseif DATE_SYMBOLS[field] then
		append_items(items, date_suggestions(opts.context, state))
	elseif field == "recurrence" then
		append_items(items, RECURRENCE_SUGGESTIONS)
	elseif field == "on_completion" then
		append_items(items, ON_COMPLETION_SUGGESTIONS)
	elseif field == "id" then
		append_items(items, id_suggestions(state))
	elseif field == "depends_on" then
		append_items(items, depends_on_suggestions(state))
	end
	return items
end

local function item_filter_texts(item)
	local texts = {
		item.word,
		item.abbr,
	}
	if type(item.filter_text) == "table" then
		for _, value in ipairs(item.filter_text) do
			table.insert(texts, value)
		end
	elseif item.filter_text then
		table.insert(texts, item.filter_text)
	end
	return texts
end

local function matches_base(item, base)
	base = trim(base):lower()
	if base == "" then
		return true
	end
	for _, text in ipairs(item_filter_texts(item)) do
		text = tostring(text or ""):lower()
		if text:find(base, 1, true) == 1 then
			return true
		end
	end
	return false
end

function M.suggest(opts)
	opts = opts or {}
	local items = {}
	for _, item in ipairs(field_suggestions(opts.field, opts.state, opts)) do
		if matches_base(item, opts.base or "") then
			table.insert(items, item)
		end
	end

	local max_items = M.config_number(get_config(), "auto_suggest_max_items", "autoSuggestMaxItems", 20)
	while #items > max_items do
		table.remove(items)
	end
	return items
end

function M.form_context(opts)
	opts = opts or {}
	local buf
	if type(opts) == "table" then
		buf = opts.buf or opts.buffer or vim.api.nvim_get_current_buf()
	else
		buf = opts or vim.api.nvim_get_current_buf()
		opts = {}
	end
	local row, col
	if opts.row and opts.cursor_col then
		row = opts.row
		col = opts.cursor_col
	else
		row, col = unpack(vim.api.nvim_win_get_cursor(0))
	end
	local line = opts.line or (vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or "")
	local before_cursor = line:sub(1, col)
	local prefix, field, value = before_cursor:match("^(([%w_]+):%s*)(.*)$")
	if not field then
		return nil
	end

	local base = value
	local start_col = #prefix
	if field == "depends_on" then
		local head, tail = value:match("^(.*,%s*)([^,]*)$")
		if head then
			base = tail
			start_col = #prefix + #head
		end
	end

	return {
		context = "form",
		field = field,
		base = base,
		row = row,
		cursor_col = col,
		start_col = start_col,
		line_length = #line,
		completefunc_start_col = start_col,
		complete_start_col = start_col + 1,
	}
end

local function current_token_context(line, before_cursor, row, col)
	local token_start, base = before_cursor:match("()([^%s]*)$")
	token_start = token_start or (#before_cursor + 1)
	base = base or ""
	local start_col = token_start - 1
	return {
		context = "markdown",
		field = "markdown_priority",
		base = base,
		row = row,
		cursor_col = col,
		start_col = start_col,
		line_length = #line,
		completefunc_start_col = start_col,
		complete_start_col = start_col + 1,
	}
end

local function latest_symbol(before_cursor)
	local best = nil
	for _, entry in ipairs(MARKDOWN_SYMBOLS) do
		local start = 1
		while true do
			local found_start, found_end = before_cursor:find(entry.symbol, start, true)
			if not found_start then
				break
			end
			if not best or found_end > best.finish then
				best = {
					field = entry.field,
					symbol = entry.symbol,
					start = found_start,
					finish = found_end,
				}
			end
			start = found_end + 1
		end
	end
	return best
end

function M.markdown_context(opts)
	opts = opts or {}
	local buf = opts.buf or opts.buffer or vim.api.nvim_get_current_buf()
	local row, col
	if opts.row and opts.cursor_col then
		row = opts.row
		col = opts.cursor_col
	else
		row, col = unpack(vim.api.nvim_win_get_cursor(0))
	end
	local line = opts.line or (vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or "")
	if not opts.cursor_col and not vim.api.nvim_get_mode().mode:match("^i") and col < #line then
		col = col + 1
	end
	if not task_model.parse_line({ line = line, global_filter = "" }) then
		return nil
	end

	local before_cursor = line:sub(1, col)
	local symbol = latest_symbol(before_cursor)
	if not symbol then
		return current_token_context(line, before_cursor, row, col)
	end

	local raw_value = before_cursor:sub(symbol.finish + 1)
	local leading = raw_value:match("^%s*") or ""
	local base = raw_value:sub(#leading + 1)
	local start_col = symbol.finish + #leading
	if symbol.field == "depends_on" then
		local head, tail = base:match("^(.*,%s*)([^,]*)$")
		if head then
			start_col = start_col + #head
			base = tail
		end
	end

	return {
		context = "markdown",
		field = symbol.field,
		base = base,
		row = row,
		cursor_col = col,
		start_col = start_col,
		line_length = #line,
		completefunc_start_col = start_col,
		complete_start_col = start_col + 1,
	}
end

function M.apply_completion(item, ctx, buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not item or not ctx or not item.word then
		return false
	end
	local row = ctx.row or vim.api.nvim_win_get_cursor(0)[1]
	local end_col = ctx.cursor_col or vim.api.nvim_win_get_cursor(0)[2]
	vim.api.nvim_buf_set_text(buf, row - 1, ctx.start_col, row - 1, end_col, { item.word })
	vim.api.nvim_win_set_cursor(0, { row, ctx.start_col + #item.word })
	return true
end

local function format_item(item)
	if item.menu and item.menu ~= "" then
		return string.format("%s\t%s", item.abbr or item.word, item.menu)
	end
	return item.abbr or item.word
end

function M.trigger_form_complete(buf, state)
	buf = buf or vim.api.nvim_get_current_buf()
	local ctx = M.form_context(buf)
	if not ctx then
		return false
	end
	local items = M.suggest({
		context = "form",
		field = ctx.field,
		base = ctx.base,
		state = state,
	})
	if #items == 0 then
		return false
	end
	pcall(vim.fn.complete, ctx.complete_start_col, items)
	return true
end

function M.trigger_markdown_complete(opts)
	opts = opts or {}
	local buf = opts.buf or opts.buffer or vim.api.nvim_get_current_buf()
	local ctx = M.markdown_context({ buf = buf })
	if not ctx then
		vim.notify("Cursor is not on a Markdown task field", vim.log.levels.WARN)
		return false
	end
	local items = M.suggest({
		context = "markdown",
		field = ctx.field,
		base = ctx.base,
		state = opts.state,
	})
	if #items == 0 then
		vim.notify("No task suggestions", vim.log.levels.INFO)
		return false
	end

	if vim.api.nvim_get_mode().mode:match("^i") then
		pcall(vim.fn.complete, ctx.complete_start_col, items)
		return true
	end

	vim.ui.select(items, {
		prompt = "Task completion",
		format_item = format_item,
	}, function(item)
		if item then
			M.apply_completion(item, ctx, buf)
		end
	end)
	return true
end

function M.complete(findstart, base)
	local ctx = M.markdown_context({ buf = vim.api.nvim_get_current_buf() })
	if tonumber(findstart) == 1 then
		return ctx and ctx.completefunc_start_col or -2
	end
	if not ctx then
		return {}
	end
	return M.suggest({
		context = "markdown",
		field = ctx.field,
		base = base,
	})
end

return M
