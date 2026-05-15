local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function parse_ymd(value)
	local year, month, day = tostring(value or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not year then
		return nil
	end
	return tonumber(year), tonumber(month), tonumber(day)
end

local function is_leap_year(year)
	return year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)
end

local function days_in_month(year, month)
	local days = {
		31,
		is_leap_year(year) and 29 or 28,
		31,
		30,
		31,
		30,
		31,
		31,
		30,
		31,
		30,
		31,
	}
	return days[month]
end

function M.is_valid(value)
	local year, month, day = parse_ymd(value)
	if not year then
		return false
	end
	if month < 1 or month > 12 then
		return false
	end
	local max_day = days_in_month(year, month)
	return day >= 1 and day <= max_day
end

function M.today()
	return os.date("%Y-%m-%d")
end

function M.add_days(value, days)
	if not M.is_valid(value) then
		return nil
	end

	local year, month, day = parse_ymd(value)
	local timestamp = os.time({
		year = year,
		month = month,
		day = day + days,
		hour = 12,
		min = 0,
		sec = 0,
	})
	return os.date("%Y-%m-%d", timestamp)
end

function M.add_months(value, months)
	if not M.is_valid(value) then
		return nil
	end

	local year, month, day = parse_ymd(value)
	local target_month = month + months
	year = year + math.floor((target_month - 1) / 12)
	month = ((target_month - 1) % 12) + 1
	day = math.min(day, days_in_month(year, month))

	return string.format("%04d-%02d-%02d", year, month, day)
end

function M.parse_date_expr(value, opts)
	opts = opts or {}
	local expr = trim(value):lower()
	if expr == "" then
		return nil
	end

	local today = opts.today or M.today()
	if expr == "today" then
		return today
	elseif expr == "tomorrow" then
		return M.add_days(today, 1)
	elseif expr == "yesterday" then
		return M.add_days(today, -1)
	end

	if M.is_valid(expr) then
		return expr
	end

	return nil
end

function M.compare(left, right)
	if not M.is_valid(left) or not M.is_valid(right) then
		return nil
	end
	if left < right then
		return -1
	elseif left > right then
		return 1
	end
	return 0
end

local DATE_FIELDS = {
	due = "due_date",
	scheduled = "scheduled_date",
	start = "start_date",
	starts = "start_date",
	done = "done_date",
	created = "created_date",
	cancelled = "cancelled_date",
	canceled = "cancelled_date",
	happens = "happens_date",
}

function M.normalize_field(field)
	return DATE_FIELDS[(field or ""):lower()]
end

function M.happens_date(task)
	local best
	for _, field in ipairs({ "start_date", "scheduled_date", "due_date" }) do
		local value = task[field]
		if M.is_valid(value) and (not best or value < best) then
			best = value
		end
	end
	return best
end

function M.get_task_date(task, field)
	local normalized = M.normalize_field(field)
	if normalized == "happens_date" then
		return task.happens_date or M.happens_date(task)
	end
	if normalized then
		return task[normalized]
	end
	return nil
end

function M.matches(value, op, expected)
	if not M.is_valid(value) or not M.is_valid(expected) then
		return false
	end

	if op == "on" then
		return value == expected
	elseif op == "before" then
		return value < expected
	elseif op == "after" then
		return value > expected
	elseif op == "on_or_before" then
		return value <= expected
	elseif op == "on_or_after" then
		return value >= expected
	end

	return false
end

return M
