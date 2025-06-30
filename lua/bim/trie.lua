local ipairs = ipairs
local next = next
local tbl_concat = table.concat
local type = type

local SHIFT_PATTERN = "^((<S%-[zxcvbnm,%.%/asdfghjkl;'qwertyuiop%[%]\\`1234567891%-=]>)+)$"

local SHIFT_MAP = {
	["a"] = "A",
	["b"] = "B",
	["c"] = "C",
	["d"] = "D",
	["e"] = "E",
	["f"] = "F",
	["g"] = "G",
	["h"] = "H",
	["i"] = "I",
	["j"] = "J",
	["k"] = "K",
	["l"] = "L",
	["m"] = "M",
	["n"] = "N",
	["o"] = "O",
	["p"] = "P",
	["q"] = "Q",
	["r"] = "R",
	["s"] = "S",
	["t"] = "T",
	["u"] = "U",
	["v"] = "V",
	["w"] = "W",
	["x"] = "X",
	["y"] = "Y",
	["z"] = "Z",
	["`"] = "~",
	["1"] = "!",
	["2"] = "@",
	["3"] = "#",
	["4"] = "$",
	["5"] = "%",
	["6"] = "^",
	["7"] = "&",
	["8"] = "*",
	["9"] = "(",
	["0"] = ")",
	["-"] = "_",
	["="] = "+",
	[","] = "<",
	["."] = ">",
	["/"] = "?",
	[";"] = ":",
	["'"] = '"',
	["["] = "{",
	["]"] = "}",
	["\\"] = "|",
}

local M = {}
local Trie = {
	-- ["a"] = {
	--   ["b"] = {
	--     command = ""
	--   }
	--   command = ""
	--}
}

local function analyze_lhs(lhs)
	if #lhs < 2 then
		-- just manage mappings with at least 2 characters and more
		-- though if only one it eval immediately and no need to manage
		return nil
	elseif lhs:sub(1, 1) == "<" then
		-- check if a shift mapping
		local match = lhs:match(SHIFT_PATTERN)
		if not match then
			return nil
		end

		local result = {}
		local gt_pos = 1 -- skip the first '<'
		local count = 0

		while true do
			gt_pos = gt_pos + 1
			gt_pos = match:find(">", gt_pos)
			if not gt_pos then
				break
			end
			count = count + 1
			result[count] = SHIFT_MAP[match:sub(gt_pos - 1, gt_pos - 1)]
		end

		if count < 2 then
			return nil
		end

		return tbl_concat(result, "")
	end

	return lhs:match("^[%w%p ]+$")
end

local function identify_type(rhs)
	if type(rhs) == "function" then
		return "function"
	elseif type(rhs) == "string" and rhs:match("^:.*<CR>$") then
		return "command"
	end
	return "string"
end

local function insert_mapping(lhs, rhs, opts)
	lhs = analyze_lhs(lhs)
	if not lhs then
		return
	end

	local node = Trie

	for i = 1, #lhs do
		local ch = lhs:sub(i, i)
		node[ch] = node[ch] or {}
		node = node[ch]
	end

	node.command = {
		type = identify_type(rhs),
		value = rhs,
		expr = opts.expr or false,
		opts = opts or {},
	}
end

function M.build_trie()
	for _, map in ipairs(vim.api.nvim_get_keymap("i")) do
		local lhs, rhs = map.lhs, map.rhs or map.callback
		insert_mapping(lhs, rhs, {
			expr = map.expr or false,
			noremap = map.noremap or false,
			silent = map.silent or false,
		})
	end
end

function M.get_trie()
	return Trie
end

function M.remove_mapping(lhs)
	lhs = analyze_lhs(lhs)
	if not lhs then
		return
	end

	local path = {}
	local node = Trie

	for i = 1, #lhs do
		local ch = lhs:sub(i, i)
		if not node[ch] then
			return
		end
		path[i] = { parent = node, key = ch }
		node = node[ch]
	end

	-- remove the command if it exists
	if node.command then
		node.command = nil
	end

	-- clean up the path if there are no more commands
	for i = #path, 1, -1 do
		local parent, key = path[i].node, path[i].key
		if next(parent[key]) == nil then
			parent[key] = nil
		else
			break
		end
	end
end

function M.has_command(node)
	return node.command ~= nil
end

function M.get_command(node)
	return node.command
end

function M.has_child(node)
	local k = next(node)
	if k ~= "command" then
		return true
	end
	return next(node, k) ~= nil
end

M.insert_mapping = insert_mapping

return M
