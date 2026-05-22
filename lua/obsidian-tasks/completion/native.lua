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

function M.complete(findstart, base)
	return completion.complete(findstart, base)
end

function M.trigger(buf, opts)
	opts = opts or {}
	buf = buf or vim.api.nvim_get_current_buf()

	local ctx = completion.markdown_context({ buf = buf })
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
	if not ctx or ctx.field ~= "markdown_priority" then
		return false
	end
	if has_priority_symbol(line or "") then
		return false
	end
	return PRIORITY_PREFIXES[(ctx.base or ""):lower()] == true
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

	local previous_length = vim.b[buf].obsidian_tasks_native_completion_line_length
	vim.b[buf].obsidian_tasks_native_completion_line_length = ctx.line_length
	if previous_length and ctx.line_length < previous_length then
		return
	end

	vim.schedule(function()
		if vim.api.nvim_get_current_buf() ~= buf or vim.fn.pumvisible() ~= 0 then
			return
		end
		M.trigger(buf)
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
