local type = type
local M = {}

function M.to_boolean(value)
	if value == nil then
		return false
	elseif type(value) == "boolean" then
		return value
	elseif type(value) == "number" then
		return value ~= 0
	else
		return true
	end
end

function M.tobit(value)
	if value == nil then
		return 0
	elseif type(value) == "boolean" then
		return value and 1 or 0
	elseif type(value) == "number" then
		return value ~= 0 and 1 or 0
	else
		return 1
	end
end

--- Check if the mode is insert mode
--- @param mode string or table of strings representing modes
--- @return boolean true if the mode is insert mode, false otherwise
function M.is_insert_mode(mode)
	if type(mode) == "string" then
		return mode == "i"
	elseif type(mode) == "table" then
		for _, m in ipairs(mode) do
			if m == "i" then
				return true
			end
		end
	end
	return false
end

return M
