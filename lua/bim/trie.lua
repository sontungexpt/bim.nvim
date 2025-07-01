local api = vim.api
local nvim_del_keymap = api.nvim_del_keymap
local nvim_get_keymap = api.nvim_get_keymap
local ipairs, type, next = ipairs, type, next
local tbl_concat = table.concat

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
--- @class Command
--- @field mode string
--- @field lhs string
--- @field callback? function
--- @field rhs? string
--- @field opts? table
--- @field opts.expr? boolean
--- @field metadata table

--- @class TrieNode
--- @field command? Command
--- @field [string] TrieNode
local Trie = {
	-- ["a"] = {
	--   ["b"] = {
	--     command = ""
	--   }
	--   command = ""
	--}
}

local TrieBuf = {
	-- [bufnr] = {
	--   ["a"] = {
	--     ["b"] = {
	--       command = ""
	--     }
	--     command = ""
	--   }
	-- }
}

local function to_boolean(value)
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

--- Analyze the left-hand side (lhs) of a mapping.
--- Supports shift mappings and returns a normalized string.
--- If the lhs is not a valid mapping, returns nil.
--- @param lhs string? The left-hand side of the mapping.
--- @return string|nil A normalized string for shift mappings or nil if invalid.
local function analyze_lhs(lhs)
	if not lhs or type(lhs) ~= "string" then
		return nil
	elseif #lhs < 2 then
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

--- Insert a mapping into the Trie.
--- If the mapping already exists, it will be overwritten.
--- @param lhs string? The left-hand side of the mapping.
--- @param rhs string|function? The right-hand side of the mapping, can be a function.
--- @param opts? vim.keymap.set.Opts:vim.api.keyset.keymap Optional options for the mapping.
--- @return boolean True if the mapping was successfully inserted, false if the lhs is invalid.
local function insert_imap(lhs, rhs, opts, metadata, default_deleted)
	local cb = nil
	local type_rhs = type(rhs)
	if type_rhs == "function" then
		cb = rhs
		rhs = nil
	elseif type_rhs ~= "string" then
		return false
	end

	local analyzed_lhs = analyze_lhs(lhs)
	if not analyzed_lhs then
		return false
	end

	local node = Trie

	for i = 1, #analyzed_lhs do
		local ch = analyzed_lhs:sub(i, i)
		node[ch] = node[ch] or {}
		node = node[ch]
	end

	node.command = {
		mode = "i",
		callback = cb,
		lhs = analyzed_lhs,
		rhs = rhs,
		opts = opts or {},
		metadata = metadata or {},
	}

	-- remove the mapping from nvim if it exists
	if lhs and default_deleted then
		nvim_del_keymap("i", lhs)
	end

	return true
end

M.insert_imap = insert_imap

local function insert_buf_imap(bufnr, lhs, rhs, opts, metadata)
	if not bufnr or type(bufnr) ~= "number" then
		return false
	end

	local cb = nil
	local type_rhs = type(rhs)
	if type_rhs == "function" then
		cb = rhs
		rhs = nil
	elseif type_rhs ~= "string" then
		return false
	end

	local analyzed_lhs = analyze_lhs(lhs)
	if not analyzed_lhs then
		return false
	end

	local node = TrieBuf[bufnr]
	if not node then
		node = {}
		TrieBuf[bufnr] = node
	end

	for i = 1, #analyzed_lhs do
		local ch = analyzed_lhs:sub(i, i)
		node[ch] = node[ch] or {}
		node = node[ch]
	end

	node.command = {
		mode = "i",
		callback = cb,
		lhs = analyzed_lhs,
		rhs = rhs,
		opts = opts or {},
		metadata = metadata or {},
	}

	return true
end

M.insert_buf_imap = insert_buf_imap

function M.build_trie()
	for _, map in ipairs(nvim_get_keymap("i")) do
		local lhs, rhs = map.lhs, map.rhs or map.callback

		insert_imap(lhs, rhs, {
			expr = to_boolean(map.expr),
			noremap = to_boolean(map.noremap),
			nowait = to_boolean(map.nowait),
			silent = to_boolean(map.silent),
			desc = map.desc,
			buffer = map.buffer and (map.buffer == 1 and 0 or map.buffer) or nil,
		}, {
			-- lhsraw is replaced termcodes -- by nvim_get_keymap, so we can use it directly
			lhsraw = map.lhsraw,
			lhsrawalt = map.lhsrawalt,
			lnum = map.lnum,
			mode_bits = map.mode_bits,
			script = to_boolean(map.script),
			scriptversion = map.scriptversion,
			abbr = to_boolean(map.abbr),
		}, true)
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
		local p = path[i]
		local parent, key = p.parent, p.key
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

return M
