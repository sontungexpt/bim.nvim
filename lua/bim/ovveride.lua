-- override.lua
local M = {}
local trie = require("bim.trie")

local original_set = vim.keymap.set

local function is_insert_mode(mode)
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

function M.wrap()
	vim.keymap.set = function(mode, lhs, rhs, opts)
		original_set(mode, lhs, rhs, opts)
		if is_insert_mode(mode) and lhs:match("^%w+$") then
			trie.insert_mapping(lhs, rhs)
		end
	end
end

return M
