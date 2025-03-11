local M = {}

-- Any utility functions that might be needed across modules

-- Function to safely require a module
function M.safe_require(module)
  local ok, result = pcall(require, module)
  if not ok then
    vim.notify("Failed to load module: " .. module, vim.log.levels.ERROR)
    return nil
  end
  return result
end

return M
