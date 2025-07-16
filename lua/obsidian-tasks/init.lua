local M = {}

-- Re-export functions from other modules
function M.setup(config)
	-- Load modules
	local core = require("obsidian-tasks.core")

	-- Initialize with config
	config = config or {}
	local vault_path = config.vault_path or "/Users/didi/Notes"

	-- Default display options
	config.display = config.display or {}
	config.display.hierarchical_headings = config.display.hierarchical_headings or false

	-- Register tree-sitter parser
	vim.treesitter.language.register("markdown", "obstasks")

	-- Store config for other modules to access
	M.config = config

	return M
end

-- Re-export main API functions
function M.find_tasks(opts)
	opts = opts or {}

	-- Apply global config options if not specified in the call
	if M.config and M.config.display then
		if opts.hierarchical_headings == nil then
			opts.hierarchical_headings = M.config.display.hierarchical_headings
		end
	end

	return require("obsidian-tasks.finder").find_tasks(opts)
end

function M.save_current_tasks()
	return require("obsidian-tasks.core").save_current_tasks()
end

function M.toggle_task_at_cursor()
	return require("obsidian-tasks.core").toggle_task_at_cursor()
end

return M
