local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local MONTHS = {
	jan = 1,
	january = 1,
	feb = 2,
	february = 2,
	mar = 3,
	march = 3,
	apr = 4,
	april = 4,
	may = 5,
	jun = 6,
	june = 6,
	jul = 7,
	july = 7,
	aug = 8,
	august = 8,
	sep = 9,
	sept = 9,
	september = 9,
	oct = 10,
	october = 10,
	nov = 11,
	november = 11,
	dec = 12,
	december = 12,
}

local WEEKDAYS = {
	sun = 0,
	sunday = 0,
	mon = 1,
	monday = 1,
	tue = 2,
	tues = 2,
	tuesday = 2,
	wed = 3,
	wednesday = 3,
	thu = 4,
	thur = 4,
	thurs = 4,
	thursday = 4,
	fri = 5,
	friday = 5,
	sat = 6,
	saturday = 6,
}

local DATE_ABBREVIATIONS = {
	td = "today",
	tm = "tomorrow",
	yd = "yesterday",
	tw = "this week",
	nw = "next week",
	we = "sat",
	weekend = "sat",
}

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

local function weekday(value)
	if not M.is_valid(value) then
		return nil
	end
	local year, month, day = parse_ymd(value)
	return tonumber(os.date("%w", os.time({
		year = year,
		month = month,
		day = day,
		hour = 12,
		min = 0,
		sec = 0,
	})))
end

local function add_weekday(today, target, mode)
	local current = weekday(today)
	if current == nil then
		return nil
	end

	local delta = target - current
	if mode == "next" then
		if delta <= 0 then
			delta = delta + 7
		end
	elseif mode == "last" then
		if delta >= 0 then
			delta = delta - 7
		end
	elseif delta < 0 then
		delta = delta + 7
	end

	return M.add_days(today, delta)
end

local function expand_abbreviation(expr)
	return DATE_ABBREVIATIONS[expr] or expr
end

local function add_units(today, amount, unit)
	amount = tonumber(amount)
	if not amount then
		return nil
	end

	unit = (unit or ""):lower()
	if unit:match("^days?$") or unit == "d" then
		return M.add_days(today, amount)
	elseif unit:match("^weeks?$") or unit == "w" then
		return M.add_days(today, amount * 7)
	elseif unit:match("^months?$") or unit == "mo" then
		return M.add_months(today, amount)
	elseif unit:match("^years?$") or unit == "y" then
		return M.add_months(today, amount * 12)
	end
	return nil
end

local function parse_named_month(expr, today)
	local today_year = parse_ymd(today)
	local day, month_name, year = expr:match("^(%d+)%s+([%a]+)%s*(%d*)$")
	if not day then
		month_name, day, year = expr:match("^([%a]+)%s+(%d+)%s*(%d*)$")
	end
	if not day then
		return nil
	end

	local month = MONTHS[(month_name or ""):lower()]
	if not month then
		return nil
	end
	year = tonumber(year ~= "" and year or nil) or today_year
	if not year then
		return nil
	end

	local value = string.format("%04d-%02d-%02d", year, month, tonumber(day))
	if M.is_valid(value) then
		return value
	end
	return nil
end

function M.parse_date_expr(value, opts)
	opts = opts or {}
	local expr = expand_abbreviation(trim(value):lower())
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

	if expr == "this week" or expr == "this month" or expr == "this year" then
		return today
	end

	local weekday_name = expr:match("^this%s+([%a]+)$")
	if weekday_name and WEEKDAYS[weekday_name] ~= nil then
		return add_weekday(today, WEEKDAYS[weekday_name], "this")
	end

	weekday_name = expr:match("^next%s+([%a]+)$")
	if weekday_name and WEEKDAYS[weekday_name] ~= nil then
		return add_weekday(today, WEEKDAYS[weekday_name], "next")
	end

	weekday_name = expr:match("^last%s+([%a]+)$")
	if weekday_name and WEEKDAYS[weekday_name] ~= nil then
		return add_weekday(today, WEEKDAYS[weekday_name], "last")
	end

	if WEEKDAYS[expr] ~= nil then
		return add_weekday(today, WEEKDAYS[expr], "this")
	end

	local amount, unit = expr:match("^in%s+([%+%-]?%d+)%s*([%a]+)$")
	if amount and unit then
		local parsed = add_units(today, amount, unit)
		if parsed then
			return parsed
		end
	end

	amount, unit = expr:match("^([%+%-]?%d+)%s*([%a]+)$")
	if amount and unit then
		local parsed = add_units(today, amount, unit)
		if parsed then
			return parsed
		end
	end

	amount = expr:match("^%+(%d+)$")
	if amount then
		return M.add_days(today, tonumber(amount))
	end

	amount = expr:match("^%-(%d+)$")
	if amount then
		return M.add_days(today, -tonumber(amount))
	end

	unit = expr:match("^next%s+([%a]+)$")
	if unit then
		return add_units(today, 1, unit)
	end

	unit = expr:match("^last%s+([%a]+)$")
	if unit then
		return add_units(today, -1, unit)
	end

	local named_month = parse_named_month(expr, today)
	if named_month then
		return named_month
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

function M.days_between(left, right)
	if not M.is_valid(left) or not M.is_valid(right) then
		return nil
	end

	local left_year, left_month, left_day = parse_ymd(left)
	local right_year, right_month, right_day = parse_ymd(right)
	local left_time = os.time({
		year = left_year,
		month = left_month,
		day = left_day,
		hour = 12,
		min = 0,
		sec = 0,
	})
	local right_time = os.time({
		year = right_year,
		month = right_month,
		day = right_day,
		hour = 12,
		min = 0,
		sec = 0,
	})
	return math.floor((left_time - right_time) / (24 * 60 * 60) + 0.5)
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

	if op == "on" or op == "in" then
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
