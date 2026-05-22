local completion = require("obsidian-tasks.completion")

local M = {}

local GROUP = "ObsidianTasksNativeCompletion"
local COMPLETEFUNC = "v:lua.obsidian_tasks_native_complete"

local METADATA_TRIGGERS = {
	["➕"] = true,
	["🛫"] = true,
	["⏳"] = true,
	["📅"] = true,
	["✅"] = true,
	["❌"] = true,
	["🔁"] = true,
	["🏁"] = true,
	["🆔"] = true,
	["⛔"] = true,
}

local PRIORITY_PREFIXES = {
	h = true,
	hi = true,
	hig = true,
	high = true,
	highest = true,
	m = true,
	me = true,
	med = true,
	medium = true,
	l = true,
	lo = true,
	low = true,
	lowest = true,
}

local PRIORITY_SYMBOLS = {
	"🔺",
	"⏫",
	"🔼",
	"🔽",
	"⏬",
}

local DATE_FIELD_PREFIXES = {
	du = true,
	due = true,
	sch = true,
	schd = true,
	schdu = true,
	schdul = true,
	schdule = true,
	schduled = true,
	sche = true,
	sched = true,
	schedu = true,
	schedul = true,
	schedule = true,
	scheduled = true,
}

local DATE_VALUE_FIELDS = {
	created = true,
	start = true,
	scheduled = true,
	due = true,
	done = true,
	cancelled = true,
}

local DATE_VALUE_PREFIXES = {
	t = true,
	to = true,
	tod = true,
	toda = true,
	today = true,
	tom = true,
	tomo = true,
	tomor = true,
	tomorr = true,
	tomorro = true,
	tomorrow = true,
	y = true,
	ye = true,
	yes = true,
	yest = true,
	yeste = true,
	yester = true,
	yesterd = true,
	yesterda = true,
	yesterday = true,
	n = true,
	ne = true,
	nex = true,
	next = true,
	["+"] = true,
	["+1"] = true,
	["+7"] = true,
}

local current_options = nil

local function get_config()
	local ok, plugin = pcall(require, "obsidian-tasks")
	if ok and plugin then
		return plugin.config or {}
	end
	return {}
end

local function normalize_options(opts)
	if opts == true then
		opts = { enabled = true }
	elseif type(opts) ~= "table" then
		opts = {}
	end

	local auto_trigger = opts.auto_trigger or opts.autoTrigger
	if auto_trigger == true then
		auto_trigger = { enabled = true }
	elseif type(auto_trigger) ~= "table" then
		auto_trigger = {}
	end

	local metadata_symbols = auto_trigger.metadata_symbols
	if metadata_symbols == nil then
		metadata_symbols = auto_trigger.metadataSymbols
	end
	if metadata_symbols == nil then
		metadata_symbols = true
	end

	local priority_prefix = auto_trigger.priority_prefix
	if priority_prefix == nil then
		priority_prefix = auto_trigger.priorityPrefix
	end

	local date_keywords = auto_trigger.date_keywords
	if date_keywords == nil then
		date_keywords = auto_trigger.dateKeywords
	end
	if date_keywords == nil then
		date_keywords = true
	end

	local date_values = auto_trigger.date_values
	if date_values == nil then
		date_values = auto_trigger.dateValues
	end
	if date_values == nil then
		date_values = true
	end

	local keymap = opts.keymap
	if keymap == nil then
		keymap = "<M-Space>"
	elseif keymap == true then
		keymap = "<M-Space>"
	end

	return {
		enabled = opts.enabled == true,
		completefunc = opts.completefunc ~= false,
		keymap = keymap,
		auto_trigger = {
			enabled = auto_trigger.enabled == true,
			metadata_symbols = metadata_symbols ~= false,
			priority_prefix = priority_prefix == true,
			date_keywords = date_keywords ~= false,
			date_values = date_values ~= false,
		},
	}
end

local function native_options()
	if current_options then
		return current_options
	end

	local config = get_config()
	local completion_config = config.completion or {}
	current_options = normalize_options(completion_config.native or completion_config.native_completion)
	return current_options
end

local function is_markdown_buffer(buf)
	local ft = vim.bo[buf].filetype
	return ft == "markdown" or ft == "md"
end

local function has_priority_symbol(line)
	for _, symbol in ipairs(PRIORITY_SYMBOLS) do
		if line:find(symbol, 1, true) then
			return true
		end
	end
	return false
end

local function latest_metadata_before(line, index)
	local best = nil
	for symbol, _ in pairs(METADATA_TRIGGERS) do
		local start = 1
		while true do
			local found_start, found_end = line:find(symbol, start, true)
			if not found_start or found_start >= index then
				break
			end
			if found_end < index and (not best or found_end > best.finish) then
				best = {
					symbol = symbol,
					start = found_start,
					finish = found_end,
				}
			end
			start = found_end + 1
		end
	end
	return best
end

local function token_starts_metadata_value(line, token_start)
	local symbol = latest_metadata_before(line, token_start)
	if not symbol then
		return false
	end
	local between = line:sub(symbol.finish + 1, token_start - 1)
	return between:match("^%s*$") ~= nil
end

local function priority_token_context(ctx, line)
	if not ctx then
		return nil
	end

	line = line or ""
	local before_cursor = line:sub(1, ctx.cursor_col or #line)
	local token_start, base = before_cursor:match("()([^%s]*)$")
	token_start = token_start or (#before_cursor + 1)
	base = base or ""

	if not PRIORITY_PREFIXES[base:lower()] then
		return nil
	end
	if token_starts_metadata_value(line, token_start) then
		return nil
	end

	return {
		context = "markdown",
		field = "markdown_priority",
		base = base,
		row = ctx.row,
		cursor_col = ctx.cursor_col,
		start_col = token_start - 1,
		line_length = #line,
		completefunc_start_col = token_start - 1,
		complete_start_col = token_start,
	}
end

local function date_keyword_context(ctx, line)
	if not ctx then
		return nil
	end

	line = line or ""
	local before_cursor = line:sub(1, ctx.cursor_col or #line)
	local token_start, base = before_cursor:match("()([^%s]*)$")
	token_start = token_start or (#before_cursor + 1)
	base = base or ""

	if not DATE_FIELD_PREFIXES[base:lower()] then
		return nil
	end
	if token_starts_metadata_value(line, token_start) then
		return nil
	end

	return {
		context = "markdown",
		field = "markdown_priority",
		base = base,
		row = ctx.row,
		cursor_col = ctx.cursor_col,
		start_col = token_start - 1,
		line_length = #line,
		completefunc_start_col = token_start - 1,
		complete_start_col = token_start,
	}
end

local function date_value_context(ctx)
	if not ctx or not DATE_VALUE_FIELDS[ctx.field] then
		return nil
	end

	local base = (ctx.base or ""):lower()
	if DATE_VALUE_PREFIXES[base] or base:match("^next%s+[%a]*$") or base:match("^%d+%s*[%a]*$") then
		return ctx
	end

	return nil
end

function M.complete(findstart, base)
	local ctx = completion.markdown_context({ buf = vim.api.nvim_get_current_buf() })
	if ctx then
		local line = vim.api.nvim_get_current_line()
		ctx = priority_token_context(ctx, line) or date_keyword_context(ctx, line) or ctx
		if tonumber(findstart) == 1 then
			return ctx.completefunc_start_col
		end
		return completion.suggest({
			context = "markdown",
			field = ctx.field,
			base = base,
		})
	end
	return completion.complete(findstart, base)
end

function M.trigger(buf, opts)
	opts = opts or {}
	buf = buf or vim.api.nvim_get_current_buf()

	local ctx = opts.context or completion.markdown_context({ buf = buf })
	if not ctx then
		if opts.notify then
			vim.notify("Cursor is not on a Markdown task field", vim.log.levels.WARN)
		end
		return false
	end

	local items = completion.suggest({
		context = "markdown",
		field = ctx.field,
		base = ctx.base,
		state = opts.state,
	})
	if #items == 0 then
		if opts.notify then
			vim.notify("No task suggestions", vim.log.levels.INFO)
		end
		return false
	end

	if vim.api.nvim_get_mode().mode:match("^i") then
		pcall(vim.fn.complete, ctx.complete_start_col, items)
		return true
	end

	return require("obsidian-tasks").complete_at_cursor({ buffer = buf })
end

function M.is_metadata_trigger(char)
	return METADATA_TRIGGERS[char] == true
end

function M.should_auto_trigger_priority(ctx, line, opts)
	opts = opts or native_options()
	if not (opts.auto_trigger and opts.auto_trigger.priority_prefix) then
		return false
	end
	if not ctx then
		return false
	end
	if has_priority_symbol(line or "") then
		return false
	end
	if ctx.field == "markdown_priority" then
		return PRIORITY_PREFIXES[(ctx.base or ""):lower()] == true
	end
	return priority_token_context(ctx, line) ~= nil
end

function M.should_auto_trigger_date_keyword(ctx, line, opts)
	opts = opts or native_options()
	if not (opts.auto_trigger and opts.auto_trigger.date_keywords) then
		return false
	end
	if not ctx then
		return false
	end
	return date_keyword_context(ctx, line) ~= nil
end

function M.should_auto_trigger_date_value(ctx, opts)
	opts = opts or native_options()
	if not (opts.auto_trigger and opts.auto_trigger.date_values) then
		return false
	end
	return date_value_context(ctx) ~= nil
end

function M.attach(buf, opts)
	buf = buf or vim.api.nvim_get_current_buf()
	opts = opts or native_options()
	if not opts.enabled or not vim.api.nvim_buf_is_valid(buf) or not is_markdown_buffer(buf) then
		return false
	end

	if opts.completefunc then
		vim.api.nvim_set_option_value("completefunc", COMPLETEFUNC, { buf = buf })
	end

	if opts.keymap and opts.keymap ~= "" and opts.keymap ~= false then
		vim.keymap.set({ "i", "n" }, opts.keymap, function()
			M.trigger(buf, { notify = true })
		end, {
			buffer = buf,
			noremap = true,
			silent = true,
			desc = "Complete Obsidian task field",
		})
	end

	vim.b[buf].obsidian_tasks_native_completion = true
	return true
end

local function maybe_trigger_metadata(buf, opts)
	if not (opts.auto_trigger.enabled and opts.auto_trigger.metadata_symbols) then
		return
	end
	if not M.is_metadata_trigger(vim.v.char) then
		return
	end

	vim.schedule(function()
		if vim.api.nvim_get_current_buf() ~= buf or vim.fn.pumvisible() ~= 0 then
			return
		end
		M.trigger(buf)
	end)
end

local function maybe_trigger_priority(buf, opts)
	if not (opts.auto_trigger.enabled and opts.auto_trigger.priority_prefix) then
		return
	end
	if vim.fn.pumvisible() ~= 0 then
		return
	end

	local line = vim.api.nvim_get_current_line()
	local ctx = completion.markdown_context({ buf = buf })
	if not M.should_auto_trigger_priority(ctx, line, opts) then
		return
	end
	local priority_ctx = priority_token_context(ctx, line) or ctx

	local previous_length = vim.b[buf].obsidian_tasks_native_completion_line_length
	vim.b[buf].obsidian_tasks_native_completion_line_length = priority_ctx.line_length
	if previous_length and priority_ctx.line_length < previous_length then
		return
	end

	vim.schedule(function()
		if vim.api.nvim_get_current_buf() ~= buf or vim.fn.pumvisible() ~= 0 then
			return
		end
		M.trigger(buf, { context = priority_ctx })
	end)
end

local function maybe_trigger_date_keyword(buf, opts)
	if not (opts.auto_trigger.enabled and opts.auto_trigger.date_keywords) then
		return
	end
	if vim.fn.pumvisible() ~= 0 then
		return
	end

	local line = vim.api.nvim_get_current_line()
	local ctx = completion.markdown_context({ buf = buf })
	if not M.should_auto_trigger_date_keyword(ctx, line, opts) then
		return
	end
	local field_ctx = date_keyword_context(ctx, line)

	local previous_length = vim.b[buf].obsidian_tasks_native_completion_line_length
	vim.b[buf].obsidian_tasks_native_completion_line_length = field_ctx.line_length
	if previous_length and field_ctx.line_length < previous_length then
		return
	end

	vim.schedule(function()
		if vim.api.nvim_get_current_buf() ~= buf or vim.fn.pumvisible() ~= 0 then
			return
		end
		M.trigger(buf, { context = field_ctx })
	end)
end

local function maybe_trigger_date_value(buf, opts)
	if not (opts.auto_trigger.enabled and opts.auto_trigger.date_values) then
		return
	end
	if vim.fn.pumvisible() ~= 0 then
		return
	end

	local ctx = completion.markdown_context({ buf = buf })
	if not M.should_auto_trigger_date_value(ctx, opts) then
		return
	end

	local previous_length = vim.b[buf].obsidian_tasks_native_completion_line_length
	vim.b[buf].obsidian_tasks_native_completion_line_length = ctx.line_length
	if previous_length and ctx.line_length < previous_length then
		return
	end

	vim.schedule(function()
		if vim.api.nvim_get_current_buf() ~= buf or vim.fn.pumvisible() ~= 0 then
			return
		end
		M.trigger(buf, { context = ctx })
	end)
end

function M.setup(opts)
	current_options = normalize_options(opts)
	if not current_options.enabled then
		return false
	end

	_G.obsidian_tasks_native_complete = function(findstart, base)
		return M.complete(findstart, base)
	end

	local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = { "markdown", "md" },
		callback = function(event)
			M.attach(event.buf, current_options)
		end,
	})

	vim.api.nvim_create_autocmd("InsertCharPre", {
		group = group,
		pattern = { "*.md", "*.markdown" },
		callback = function(event)
			if is_markdown_buffer(event.buf) then
				maybe_trigger_metadata(event.buf, current_options)
			end
		end,
	})

	vim.api.nvim_create_autocmd("TextChangedI", {
		group = group,
		pattern = { "*.md", "*.markdown" },
		callback = function(event)
			if is_markdown_buffer(event.buf) then
				maybe_trigger_priority(event.buf, current_options)
				maybe_trigger_date_keyword(event.buf, current_options)
				maybe_trigger_date_value(event.buf, current_options)
			end
		end,
	})

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and is_markdown_buffer(buf) then
			M.attach(buf, current_options)
		end
	end

	return true
end

return M
