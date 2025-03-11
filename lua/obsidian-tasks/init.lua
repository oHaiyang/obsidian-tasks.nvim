local M = {}

-- Re-export functions from other modules
function M.setup(config)
  -- Load modules
  local core = require("obsidian-tasks.core")
  
  -- Initialize with config
  config = config or {}
  local vault_path = config.vault_path or "/Users/didi/Notes"

  -- Register tree-sitter parser
  vim.treesitter.language.register("markdown", "obstasks")
  
  -- Store config for other modules to access
  M.config = config
  
  return M
end

-- Re-export main API functions
function M.find_tasks(opts)
  return require("obsidian-tasks.finder").find_tasks(opts)
end

function M.save_current_tasks()
  return require("obsidian-tasks.core").save_current_tasks()
end

function M.toggle_task_at_cursor()
  return require("obsidian-tasks.core").toggle_task_at_cursor()
end

return M
