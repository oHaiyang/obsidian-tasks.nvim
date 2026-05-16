local completion = require("obsidian-tasks.completion")

local M = {}
local Source = {}
Source.__index = Source

local function current_context(params)
	local context = (params and params.context) or {}
	local buf = context.bufnr or vim.api.nvim_get_current_buf()
	local row = context.row
	local line = context.cursor_line
	local before = context.cursor_before_line

	if not line or line == "" then
		local win_row = vim.api.nvim_win_get_cursor(0)[1]
		row = row or win_row
		line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	end
	row = row or vim.api.nvim_win_get_cursor(0)[1]

	local cursor_col = before and #before or nil
	if not cursor_col then
		local _, col = unpack(vim.api.nvim_win_get_cursor(0))
		cursor_col = col
	end

	return {
		buf = buf,
		row = row,
		line = line,
		cursor_col = cursor_col,
		filetype = context.filetype or vim.bo[buf].filetype,
	}
end

local function completion_kind()
	local ok, cmp = pcall(require, "cmp")
	if ok and cmp and cmp.lsp and cmp.lsp.CompletionItemKind then
		return cmp.lsp.CompletionItemKind.Value
	end
	return nil
end

local function to_cmp_item(item, kind)
	local label = item.abbr or item.word
	return {
		label = label,
		insertText = item.word,
		filterText = item.filter_text or item.abbr or item.word,
		sortText = item.filter_text or item.abbr or item.word,
		detail = item.menu,
		kind = kind,
		documentation = item.menu and ("Obsidian Tasks " .. item.menu) or nil,
	}
end

local function context_for_params(params)
	local cursor = current_context(params)
	if cursor.filetype == "obstasks-form" then
		return completion.form_context(cursor)
	end
	return completion.markdown_context(cursor)
end

function Source.new(opts)
	return setmetatable({
		opts = opts or {},
		kind = completion_kind(),
	}, Source)
end

function Source:get_debug_name()
	return "obsidian-tasks"
end

function Source:is_available()
	local filetype = vim.bo.filetype
	return filetype == "markdown" or filetype == "md" or filetype == "obstasks-form"
end

function Source:get_trigger_characters()
	return { "📅", "🔁", "⛔", "🆔", "🏁", "➕", "🛫", "⏳", "✅", "❌" }
end

function Source:complete(params, callback)
	local ctx = context_for_params(params)
	if not ctx then
		callback({ items = {}, isIncomplete = false })
		return
	end

	local items = completion.suggest({
		context = ctx.context,
		field = ctx.field,
		base = ctx.base,
		state = self.opts.state,
	})
	local cmp_items = {}
	for _, item in ipairs(items) do
		table.insert(cmp_items, to_cmp_item(item, self.kind))
	end

	callback({
		items = cmp_items,
		isIncomplete = false,
		offset = ctx.complete_start_col,
	})
end

M.Source = Source

function M.new(opts)
	return Source.new(opts)
end

function M.register(opts)
	opts = opts or {}
	local ok, cmp = pcall(require, "cmp")
	if not ok or not cmp then
		return false
	end
	cmp.register_source(opts.name or "obsidian-tasks", Source.new(opts))
	return true
end

return M
