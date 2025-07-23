local M = {}

-- Store priority emoji mappings
M.PRIORITY_EMOJIS = {
	["🔺"] = "highest",
	["⏫"] = "high",
	["🔼"] = "medium",
	["🔽"] = "low",
	-- ⏬️ and ⏬ are different emojis
	["⏬️"] = "lowest",
	["⏬"] = "lowest",
}

-- Priority order (for sorting)
M.PRIORITY_ORDER = {
	highest = 1,
	high = 2,
	medium = 3,
	normal = 4,
	low = 5,
	lowest = 6,
}

-- Extract task priority
function M.extract_priority(task_text)
	for emoji, priority in pairs(M.PRIORITY_EMOJIS) do
		if task_text:find(emoji) then
			return priority
		end
	end
	return "normal"
end

-- Parse display line to task information
function M.parse_display_line(line)
	local index, status, rest = line:match("^(%d+)%. (%[.?%]) (.+)")
	-- require('plenary.log').info('[xxxhhh][parsing line]', index, status, rest);

	if not (index and status and rest) then
		return nil
	end

	-- Extract priority (if any)
	local priority = "normal"
	local text = rest

	-- Check for priority tag
	local priority_match = rest:match("^%[([%w]+)%] (.+)")
	if priority_match then
		local priority_tag = priority_match:upper()
		if
			priority_tag == "HIGHEST"
			or priority_tag == "HIGH"
			or priority_tag == "MEDIUM"
			or priority_tag == "LOW"
			or priority_tag == "LOWEST"
		then
			priority = priority_tag:lower()
			_, text = rest:match("^%[([%w]+)%] (.+)")
		end
	end
	-- require('plenary.log').info('[xxxhhh][priority and text]', priority, text);

	-- Extract file path and line number
	local file_path, line_number
	text, file_path, line_number = text:match("(.+) %[%[(.+)#L(%d+)%]%]")
	-- require('plenary.log').info('[xxxhhh][parsing file path]', text, file_path, line_number);

	if not (text and file_path and line_number) then
		return nil
	end

	return {
		index = tonumber(index),
		status = status,
		text = text,
		file_path = file_path,
		line_number = tonumber(line_number),
		priority = priority,
	}
end

-- Parse query string
function M.parse_query(query)
	local filters = {}
	if query:match("not done") then
		filters.not_done = true
	elseif query:match("done") then
		filters.done = true
	end
	local due_date = query:match("due (%d%d%d%d%-%d%d%-%d%d)")
	if due_date then
		filters.due_date = due_date
	end
	return filters
end

-- Filter tasks based on query
function M.filter_tasks(tasks, filter)
	local filtered_tasks = {}
	for _, task in ipairs(tasks) do
		local include = filter(task)
		if include then
			table.insert(filtered_tasks, task)
		end
	end
	return filtered_tasks
end

-- Group tasks by given criteria
function M.group_tasks(tasks, group_by)
	if #group_by == 0 then
		return { default = tasks }, { "default" }
	end

	-- Create groups based on given criteria
	local grouped = {}
	local group_order = {} -- To track the order of groups

	-- Recursive function to handle multiple levels of grouping
	local function process_groups(current_tasks, group_index, prefix)
		prefix = prefix or {}
		local current_group = group_by[group_index]

		if not current_group then
			-- Done processing all group levels, add tasks to result
			local key = table.concat(prefix, ":")
			if key == "" then
				key = "default"
			end
			grouped[key] = current_tasks
      -- require('plenary.log').info('[xxxhhh][insert group to result]', grouped);
			table.insert(group_order, key)
			return
		end

		-- Group tasks by current grouping type
		local sub_groups = {}
		local sub_group_names = {} -- To track the order of sub-groups

		for _, task in ipairs(current_tasks) do
			local group_value

			if current_group == "status" then
				group_value = (task.status == "[ ]") and "Pending" or "Completed"
			elseif current_group == "priority" then
				group_value = task.priority:sub(1, 1):upper() .. task.priority:sub(2)
			elseif current_group == "file" then
				-- Extract filename from file_path (without extension)
				local filename = task.file_path:match("([^/]+)%.%w+$") or task.file_path
				-- Remove extension if present
				filename = filename:gsub("%.%w+$", "")
				group_value = filename
			else
				group_value = "Other"
			end

			if not sub_groups[group_value] then
				table.insert(sub_group_names, group_value)
			end

			sub_groups[group_value] = sub_groups[group_value] or {}
			table.insert(sub_groups[group_value], task)
		end

		-- Sort sub_group_names if current_group is priority
		if current_group == "priority" then
			table.sort(sub_group_names, function(a, b)
				-- Convert group name (e.g., "Highest") to priority key (e.g., "highest")
				local a_priority = a:lower()
				local b_priority = b:lower()

				-- Use the PRIORITY_ORDER table to determine sort order
				return M.PRIORITY_ORDER[a_priority] < M.PRIORITY_ORDER[b_priority]
			end)
		end
    -- require('plenary.log').info('[xxxhhh][sorted priority group names]', sub_group_names);

		-- Recursively process next level of grouping
		for _, sub_name in ipairs(sub_group_names) do
			local sub_tasks = sub_groups[sub_name]
			local new_prefix = vim.deepcopy(prefix)
			table.insert(new_prefix, sub_name)
			process_groups(sub_tasks, group_index + 1, new_prefix)
		end
	end

	process_groups(tasks, 1)
  -- require('plenary.log').info('[xxxhhh][grouped]', group_order, grouped);
	return grouped, group_order
end

return M
