if vim.g.loaded_obsidian_tasks_nvim == 1 then
	return
end

vim.g.loaded_obsidian_tasks_nvim = 1

require("obsidian-tasks.panel").setup_commands()
