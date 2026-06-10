local type = type
local M = {}

M.to_boolean = function(value)
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

M.tobit = function(value)
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
M.is_insert_mode = function(mode)
	local t = type(mode)
	if t == "string" then
		return mode == "i"
	elseif t == "table" then
		for _, m in ipairs(mode) do
			if m == "i" then
				return true
			end
		end
	end
	return false
end

return M
