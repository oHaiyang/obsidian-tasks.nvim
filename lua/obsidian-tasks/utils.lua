---@class ObsidianTasksUtils
---@field safe_require fun(module: string): table|nil # Safely requires a module, returns nil if it fails
local M = {}

-- Any utility functions that might be needed across modules

---@param module string The name of the module to require
---@return table|nil result The required module or nil if it failed to load
function M.safe_require(module)
	local ok, result = pcall(require, module)
	if not ok then
		vim.notify("Failed to load module: " .. module, vim.log.levels.ERROR)
		return nil
	end
	return result
end

return M
