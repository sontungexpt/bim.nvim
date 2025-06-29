local type = type
-- override.lua
local M = {}

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
	local trie = require("bim.trie")
	local keymap = vim.keymap
	local original_set = keymap.set
	local original_del = keymap.del

	---@diagnostic disable-next-line: duplicate-set-field
	keymap.set = function(mode, lhs, rhs, opts)
		original_set(mode, lhs, rhs, opts)

		if is_insert_mode(mode) and lhs:match("^%w+$") then
			trie.insert_mapping(lhs, rhs, opts)
		end
	end

	---@diagnostic disable-next-line: duplicate-set-field
	keymap.del = function(mode, lhs, opts)
		original_del(mode, lhs, opts)
		if is_insert_mode(mode) and lhs:match("^%w+$") then
			trie.remove_mapping(lhs)
		end
	end
end

return M
