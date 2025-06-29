-- mapping-trie.lua
local M = {}

M.Trie = {}

local function is_valid_char(ch)
	return ch:match("[%w%p]") and #ch == 1
end

function M.build_trie()
	M.Trie = {}
	for _, map in ipairs(vim.api.nvim_get_keymap("i")) do
		local lhs, rhs = map.lhs, map.rhs
		local node = M.Trie
		local valid = true

		for i = 1, #lhs do
			local ch = lhs:sub(i, i)
			if not is_valid_char(ch) then
				valid = false
				break
			end
			node[ch] = node[ch] or {}
			node = node[ch]
		end

		if valid then
			node.command = rhs
		end
	end
end

function M.insert_mapping(lhs, rhs)
	local node = M.Trie
	for i = 1, #lhs do
		local ch = lhs:sub(i, i)
		if not is_valid_char(ch) then
			return
		end
		node[ch] = node[ch] or {}
		node = node[ch]
	end
	node.command = rhs
end

function M.get_trie()
	return M.Trie
end

return M
