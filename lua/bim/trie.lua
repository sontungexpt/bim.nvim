local type = type

local M = {}
local Trie = {}

local function is_valid_char(ch)
	return ch:match("[%w%p]") and #ch == 1
end

local function insert_mapping(lhs, rhs, opts)
	opts = opts or {}
	local node = Trie

	for i = 1, #lhs do
		local ch = lhs:sub(i, i)
		if not is_valid_char(ch) then
			return
		end
		node[ch] = node[ch] or {}
		node = node[ch]
	end

	local cmd_type
	if type(rhs) == "function" then
		cmd_type = "function"
	elseif type(rhs) == "string" and rhs:match("^:.*<CR>$") then
		cmd_type = "command"
	else
		cmd_type = "string"
	end

	node.command = {
		type = cmd_type,
		value = rhs,
		expr = opts.expr or false,
		opts = opts,
	}
end

function M.build_trie()
	Trie = {}
	for _, map in ipairs(vim.api.nvim_get_keymap("i")) do
		local lhs, rhs = map.lhs, map.rhs
		insert_mapping(lhs, rhs, {
			expr = map.expr or false,
			opts = {
				noremap = map.noremap or false,
				silent = map.silent or false,
			},
		})
	end
end

function M.get_trie()
	return Trie
end

function M.remove_mapping(lhs)
	local path = {}
	local node = M.Trie

	for i = 1, #lhs do
		local ch = lhs:sub(i, i)
		if not node[ch] then
			return
		end
		table.insert(path, { node = node, key = ch })
		node = node[ch]
	end

	-- Xóa command nếu có
	if node.command then
		node.command = nil
	end

	-- Dọn dẹp nút rỗng
	for i = #path, 1, -1 do
		local parent, key = path[i].node, path[i].key
		if next(parent[key]) == nil then
			parent[key] = nil
		else
			break
		end
	end
end

M.insert_mapping = insert_mapping
return M
