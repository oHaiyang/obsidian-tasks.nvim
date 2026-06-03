local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function wiki_parts(value)
	local destination, alias = value:match("^(.-)|(.*)$")
	destination = destination or value
	local path, subpath = destination:match("^(.-)#(.*)$")
	return {
		destination = trim(destination),
		path = trim(path or destination),
		subpath = trim(subpath or ""),
		display = trim(alias or ""),
	}
end

function M.extract(text)
	local links = {}
	text = text or ""

	for inner in text:gmatch("%[%[([^%]]+)%]%]") do
		local parts = wiki_parts(inner)
		table.insert(links, {
			type = "wiki",
			raw = "[[" .. inner .. "]]",
			destination = parts.destination,
			path = parts.path,
			subpath = parts.subpath,
			display = parts.display,
		})
	end

	for label, destination in text:gmatch("%[([^%]]+)%]%(([^%)]+)%)") do
		if not label:find("::", 1, true) then
			table.insert(links, {
				type = "markdown",
				raw = "[" .. label .. "](" .. destination .. ")",
				destination = trim(destination),
				path = trim(destination),
				display = trim(label),
			})
		end
	end

	return links
end

return M
