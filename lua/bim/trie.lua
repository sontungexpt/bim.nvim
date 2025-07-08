local api = vim.api
local nvim_del_keymap, nvim_buf_del_keymap = api.nvim_del_keymap, api.nvim_buf_del_keymap
local nvim_get_keymap, nvim_buf_get_keymap = api.nvim_get_keymap, api.nvim_buf_get_keymap
local ipairs, type, next = ipairs, type, next
local tbl_concat = table.concat

local utils = require("bim.utils")
local to_boolean, tobit = utils.to_boolean, utils.tobit

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

--- @class Cmd
--- @field mode string -- the mode of the mapping, e.g., "i" for insert mode
--- @field lhs string -- the left-hand side of the mapping, can be a normalized string for shift mappings
--- @field callback? function -- the callback function for the mapping
--- @field rhs? string -- the right-hand side of the mapping, can be a function
--- @field rhsraw? string cache for the raw rhs
--- @field opts? table -- options for the mapping, can include:
--- @field opts.expr? boolean -- if true, the rhs is evaluated as an expression
--- @field metadata table -- additional metadata for the mapping, can include:
---
--- @class TrieNode
--- @field command? Cmd -- the command associated with this node, if any
--- @field [string] TrieNode
local GTrie = {
	-- ["a"] = {
	--   ["b"] = {
	--   }
	--}
}

--- @class BufTrieNode
--- @field [integer] TrieNode
local BufTrie = {
	-- [bufnr] = {
	--   ["a"] = {
	--     ["b"] = {
	--     }
	--   }
	-- }
}

--- @class CmdRef
--- @field [TrieNode] Cmd -- a reference to the command associated with this node, if any

--- @type CmdRef
local GCmdRef = {}

--- @type table<integer, CmdRef>
local BufCmdRef = {
	-- [bufnr] = {
	--   ["a"] = {
	--     ["b"] = {
	--     }
	--   }
	-- }
}

M.delete_buf = function(bufnr)
	BufTrie[bufnr] = nil
	BufCmdRef[bufnr] = nil
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

--- Insert a mapping into the Trie from a node.
--- If the mapping already exists, it will be overwritten.
--- @param node TrieNode The node to insert the mapping into.
--- @param lhs string? The left-hand side of the mapping.
--- @param rhs string|function? The right-hand side of the mapping, can be a function.
--- @param opts? vim.keymap.set.Opts:vim.api.keyset.keymap Optional options for the mapping.
--- @param metadata? table Metadata for the mapping, can include additional information.
--- @return TrieNode|nil The node where the mapping was inserted, or nil if the lhs is invalid.
local function set_keymap_from_node(node, lhs, rhs, opts, metadata)
	local cb = nil
	local type_rhs = type(rhs)
	if type_rhs == "function" then
		cb = rhs
		rhs = nil
	elseif type_rhs ~= "string" then
		return nil
	end

	local analyzed_lhs = analyze_lhs(lhs)
	if not analyzed_lhs then
		return nil
	end

	for i = 1, #analyzed_lhs do
		local ch = analyzed_lhs:sub(i, i)
		node[ch] = node[ch] or {}
		node = node[ch]
	end

	opts = opts or {}

	node.command = {
		mode = "i",
		callback = cb or opts.callback,
		lhs = analyzed_lhs,
		rhs = rhs,
		opts = opts,
		metadata = metadata or {},
	}
	return node
end

--- Insert a mapping into the Trie.
--- If the mapping already exists, it will be overwritten.
--- @param lhs string? The left-hand side of the mapping.
--- @param rhs string|function? The right-hand side of the mapping, can be a function.
--- @param opts? vim.keymap.set.Opts:vim.api.keyset.keymap Optional options for the mapping.
--- @return boolean True if the mapping was successfully inserted, false if the lhs is invalid.
local function set_keymap(lhs, rhs, opts, metadata, default_deleted)
	local node = set_keymap_from_node(GTrie, lhs, rhs, opts, metadata)
	if not node then
		return false
	end
	GCmdRef[node] = node.command
	if lhs and default_deleted then
		nvim_del_keymap("i", lhs)
	end
	return true
end
M.set_keymap = set_keymap

--- Insert a mapping into the Trie for a specific buffer.
--- If the mapping already exists, it will be overwritten.
--- @param bufnr integer The buffer number to insert the mapping for.
--- @param lhs string? The left-hand side of the mapping.
--- @param rhs string|function? The right-hand side of the mapping, can be a function.
--- @param opts? vim.keymap.set.Opts:vim.api.keyset.keymap Optional options for the mapping.
--- @param metadata? table Metadata for the mapping, can include additional information.
--- @param default_deleted? boolean If true, the mapping will be deleted from nvim if it exists.
--- @return boolean True if the mapping was successfully inserted, false if the bufnr is invalid or lhs is invalid.
local function buf_set_keymap(bufnr, lhs, rhs, opts, metadata, default_deleted)
	if type(bufnr) ~= "number" then
		error("bufnr must be a number")
		return false
	end

	local buf_trie = BufTrie[bufnr]
	if not buf_trie then
		buf_trie = {}
		BufTrie[bufnr] = buf_trie
	end

	local node = set_keymap_from_node(buf_trie, lhs, rhs, opts, metadata)
	if not node then
		return false
	end

	local buf_cmd_ref = BufCmdRef[bufnr]
	if not buf_cmd_ref then
		buf_cmd_ref = {}
		BufCmdRef[bufnr] = buf_cmd_ref
	end

	buf_cmd_ref[node] = node.command

	if lhs and default_deleted then
		nvim_buf_del_keymap(bufnr, "i", lhs)
	end

	return true
end

M.buf_set_keymap = buf_set_keymap

local build_opts = function(map)
	return {
		expr = to_boolean(map.expr),
		noremap = to_boolean(map.noremap),
		nowait = to_boolean(map.nowait),
		silent = to_boolean(map.silent),
		desc = map.desc,
	}
end

local build_meta = function(map)
	return {
		buffer = map.buffer,
		lhsraw = map.lhsraw,
		lhsrawalt = map.lhsrawalt,
		lnum = map.lnum,
		mode_bits = map.mode_bits,
		script = map.script,
		scriptversion = map.scriptversion,
		abbr = map.abbr,
	}
end

--- Build the Trie from the current key mappings.
--- If a buffer number is provided, it will build the Trie for that buffer only.
--- @param bufnr integer|nil The buffer number to build the Trie for, or nil to build for all buffers.
function M.build_trie(bufnr)
	if type(bufnr) == "number" then
		for _, map in ipairs(nvim_buf_get_keymap(bufnr, "i")) do
			local lhs, rhs = map.lhs, map.rhs or map.callback
			buf_set_keymap(bufnr, lhs, rhs, build_opts(map), build_meta(map), true)
		end
	else
		for _, map in ipairs(nvim_get_keymap("i")) do
			local lhs, rhs = map.lhs, map.rhs or map.callback
			set_keymap(lhs, rhs, build_opts(map), build_meta(map), true)
		end
	end
end

function M.get_trie()
	return GTrie
end

function M.get_buf_trie(bufnr)
	if type(bufnr) ~= "number" then
		error("bufnr must be a number")
	end
	return BufTrie[bufnr] or {}
end

local function trie_unmap(trie, cmdref, lhs)
	if type(trie) ~= "table" or type(cmdref) ~= "table" then
		return false
	end

	lhs = analyze_lhs(lhs)
	if not lhs then
		return false
	end

	local path = {}
	local node = trie

	for i = 1, #lhs do
		local ch = lhs:sub(i, i)
		if not node[ch] then
			return false
		end
		path[i] = { parent = node, key = ch }
		node = node[ch]
	end

	if not node.command then
		return false -- no command found
	end

	-- remove the command if it exists
	node.command = nil
	cmdref[node] = nil

	-- clean up the path if there are no more commands
	for i = #path, 1, -1 do
		local p = path[i]
		local parent, key = p.parent, p.key
		local n = parent[key]
		if next(n) == nil then
			--- remove node
			parent[key] = nil
		else
			break
		end
	end
	return true
end

function M.buf_del_keymap(bufnr, lhs)
	return trie_unmap(BufTrie[bufnr], BufCmdRef[bufnr], lhs)
end

function M.del_keymap(lhs)
	return trie_unmap(GTrie, GCmdRef, lhs)
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

-- vim.api.keyset.get_keymap[]
local build_keyset_get_keymap = function(command)
	local metadata = command.metadata or {}
	local opts = command.opts or {}

	return {
		mode = command.mode,
		lhs = command.lhs,
		lhsraw = metadata.lhsraw or api.nvim_replace_termcodes(command.lhs, true, true, true),
		lhsrawalt = metadata.lhsrawalt or nil,
		rhs = command.rhs,
		callback = command.callback,
		expr = tobit(opts.expr),
		noremap = tobit(opts.noremap),
		nowait = tobit(opts.nowait),
		silent = tobit(opts.silent),
		desc = opts.desc,
		buffer = metadata.buffer or 0,
		lnum = metadata.lnum or 0,
		script = metadata.script or 0,
		scriptversion = metadata.scriptversion or 0,
		abbr = metadata.abbr or 0,
	}
end

M.get_keymap = function()
	local maps = nvim_get_keymap("i")
	for _, cmd in pairs(GCmdRef) do
		maps[#maps + 1] = build_keyset_get_keymap(cmd)
	end
	return maps
end

M.buf_get_keymap = function(bufnr)
	if type(bufnr) ~= "number" then
		error("bufnr must be a number")
	end

	local maps = nvim_buf_get_keymap(bufnr, "i")
	local buf_cmd_ref = BufCmdRef[bufnr]
	if not buf_cmd_ref then
		return maps
	end

	for _, cmd in pairs(buf_cmd_ref) do
		maps[#maps + 1] = build_keyset_get_keymap(cmd)
	end

	return maps
end

return M
