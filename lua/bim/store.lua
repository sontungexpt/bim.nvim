local api = vim.api
local nvim_del_keymap, nvim_buf_del_keymap = api.nvim_del_keymap, api.nvim_buf_del_keymap
local nvim_get_keymap, nvim_buf_get_keymap = api.nvim_get_keymap, api.nvim_buf_get_keymap
local ipairs, type = ipairs, type
local tbl_concat = table.concat

local utils = require("bim.utils")
local to_boolean, tobit = utils.to_boolean, utils.tobit

-- shift normalization (kept small and fast)
local SHIFT_PATTERN = "^((<[Ss]%-[zxcvbnm,%.%/asdfghjkl;'qwertyuiop%[%]\\`1234567891%-=]>)+)$"
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

-- Storage:
--
-- Maps store exact sequences:
--
--   GlobalMap["jk"] = Cmd
--
-- Prefix tables store the number of mappings sharing a prefix.
-- Counts include exact mappings themselves.
--
-- Example:
--
--   jk
--   jkl
--
-- Produces:
--
--   Prefix["j"]   = 2
--   Prefix["jk"]  = 2
--   Prefix["jkl"] = 1
--
-- The empty prefix ("") tracks the total number of mappings.
local GlobalMap = {} -- [seq] = Cmd
local GlobalPrefix = {} -- [prefix] = count
local BufMap = {} -- [bufnr] = { [seq] = Cmd }
local BufPrefix = {} -- [bufnr] = { [prefix] = count }

local function ensure_buf(bufnr)
	if not BufMap[bufnr] then
		BufMap[bufnr] = {}
		BufPrefix[bufnr] = {}
		BufPrefix[bufnr][""] = 0
	end
end

local function analyze_shift_group(lhs)
	local shift_match = lhs:match(SHIFT_PATTERN)
	if not shift_match then
		return nil
	end
	local result = {}
	local gt_pos = 1
	local count = 0
	while true do
		gt_pos = gt_pos + 1
		gt_pos = shift_match:find(">", gt_pos)
		if not gt_pos then
			break
		end
		count = count + 1
		result[count] = SHIFT_MAP[shift_match:sub(gt_pos - 1, gt_pos - 1)]
	end
	if count < 2 then
		return nil
	end
	return tbl_concat(result, "")
end

local function analyze_lhs(lhs)
	if not lhs or type(lhs) ~= "string" then
		return nil
	elseif #lhs < 2 then
		return nil
	elseif lhs:sub(1, 1) == "<" then
		return analyze_shift_group(lhs)
	end
	return lhs:match("^[%w%p ]+$")
end

-- Update prefix counters for a mapping.
--
-- For:
--
--   seq = "jkl"
--
-- We update:
--
--   ""
--   "j"
--   "jk"
--   "jkl"
--
-- Positive delta adds a mapping.
-- Negative delta removes a mapping.
local function add_prefix_counts(prefix_tbl, seq, delta)
	for i = 0, #seq do
		local p = seq:sub(1, i)
		prefix_tbl[p] = (prefix_tbl[p] or 0) + delta
		if prefix_tbl[p] <= 0 then
			prefix_tbl[p] = nil
		end
	end
end

local function build_cmd(seq, rhs, opts, metadata)
	local cb
	if type(rhs) == "function" then
		cb = rhs
		rhs = nil
	end
	opts = opts or {}
	return {
		mode = "i",
		lhs = seq,
		rhs = rhs,
		callback = cb or opts.callback,
		opts = opts,
		metadata = metadata or {},
	}
end

--- Add a mapping to the internal store.
---
--- @param lhs string Original lhs from a keymap.
--- @param rhs string|function Mapping rhs or callback.
--- @param opts? table Mapping options.
--- @param bufnr? integer Target buffer. Nil means global mapping.
--- @param take_ownership? boolean Remove the original Neovim keymap after importing.
---
--- @return boolean success True if the mapping was accepted.
function M.add(lhs, rhs, opts, bufnr, take_ownership)
	take_ownership = take_ownership == nil and true or take_ownership
	local seq = analyze_lhs(lhs)
	if not seq then
		return false
	end

	local map_tbl, pref_tbl
	if type(bufnr) == "number" then
		ensure_buf(bufnr)
		map_tbl = BufMap[bufnr]
		pref_tbl = BufPrefix[bufnr]
	else
		map_tbl = GlobalMap
		pref_tbl = GlobalPrefix
	end

	local existed = map_tbl[seq] ~= nil
	if not existed then
		add_prefix_counts(pref_tbl, seq, 1)
		pref_tbl[""] = (pref_tbl[""] or 0)
	end

	map_tbl[seq] = build_cmd(seq, rhs, opts)

	if take_ownership then
		if type(bufnr) == "number" then
			pcall(nvim_buf_del_keymap, bufnr, "i", lhs)
		else
			pcall(nvim_del_keymap, "i", lhs)
		end
	end

	return true
end

--- Remove a mapping from the internal store.
---
--- @param lhs string Mapping lhs.
--- @param bufnr? integer Target buffer. Nil means global mapping.
---
--- @return boolean removed True if a mapping was removed.
function M.remove(lhs, bufnr)
	local seq = analyze_lhs(lhs)
	if not seq then
		return false
	end

	if type(bufnr) == "number" then
		local map_tbl = BufMap[bufnr]
		if not map_tbl or not map_tbl[seq] then
			return false
		end
		map_tbl[seq] = nil
		local pref_tbl = BufPrefix[bufnr]
		if pref_tbl then
			add_prefix_counts(pref_tbl, seq, -1)
		end
		return true
	else
		if not GlobalMap[seq] then
			return false
		end
		GlobalMap[seq] = nil
		add_prefix_counts(GlobalPrefix, seq, -1)
		return true
	end
end

-- Build store from existing nvim mappings. If bufnr is provided build for
-- that buffer only. take_ownership controls whether we delete the original
-- nvim mappings (default: true)
local function build_opts(map)
	return {
		expr = to_boolean(map.expr),
		noremap = to_boolean(map.noremap),
		nowait = to_boolean(map.nowait),
		silent = to_boolean(map.silent),
		desc = map.desc,
	}
end

--- Rebuild internal storage from existing Neovim keymaps.
---
--- Existing state for the target scope is discarded.
---
--- @param bufnr? integer Buffer to rebuild. Nil rebuilds global mappings.
--- @param take_ownership? boolean Remove imported keymaps from Neovim.
function M.build(bufnr, take_ownership)
	take_ownership = take_ownership == nil and true or take_ownership
	if type(bufnr) == "number" then
		BufMap[bufnr] = {}
		BufPrefix[bufnr] = {}
		BufPrefix[bufnr][""] = 0
		for _, map in ipairs(nvim_buf_get_keymap(bufnr, "i")) do
			M.add(map.lhs, map.rhs or map.callback, build_opts(map), bufnr, take_ownership)
		end
	else
		GlobalMap = {}
		GlobalPrefix = {}
		GlobalPrefix[""] = 0
		for _, map in ipairs(nvim_get_keymap("i")) do
			M.add(map.lhs, map.rhs or map.callback, build_opts(map), nil, take_ownership)
		end
	end
end

--- Check whether any mapping starts with `seq`.
---
--- Uses union semantics:
---
---   Global mappings ∪ Buffer mappings
---
--- @param bufnr? integer Buffer scope to include.
--- @param seq string Normalized key sequence.
---
--- @return boolean
function M.has_prefix(bufnr, seq)
	if type(bufnr) == "number" then
		local p = BufPrefix[bufnr]
		if p and p[seq] and p[seq] > 0 then
			return true
		end
	end
	return (GlobalPrefix[seq] and GlobalPrefix[seq] > 0) or false
end

--- Resolve an exact mapping.
---
--- Resolution order:
---
---   Buffer exact mapping > Global exact mapping
---
--- @param bufnr? integer Buffer scope.
--- @param seq string Normalized key sequence.
---
--- @return table|nil cmd
function M.get_command(bufnr, seq)
	if type(bufnr) == "number" then
		local buf_map = BufMap[bufnr]
		if buf_map and buf_map[seq] then
			return buf_map[seq]
		end
	end
	return GlobalMap[seq]
end

-- Check whether `seq` has any longer mappings extending it.
--
-- Prefix counters include the mapping itself:
--
--   jk        => Prefix["jk"] = 1
--   jk, jkl   => Prefix["jk"] = 2
--
-- Therefore:
--
--   children = prefix_count - exact_count
--
-- We intentionally use UNION semantics across global and buffer-local
-- mappings instead of selecting a single "owner" scope.
--
-- Example:
--
--   Global: jk
--   Buffer: jkl
--
-- In this case `jk` must still be considered to have a child (`jkl`),
-- even though the exact match comes from the global scope and the child
-- comes from the buffer scope.
--
-- Using scope ownership would incorrectly hide children that exist in the
-- other scope and may cause mappings to execute prematurely before longer
-- sequences have a chance to match.
--
-- Exact command resolution:
--
--   Buffer exact mapping > Global exact mapping
--
-- Child detection:
--
--   Global mappings ∪ Buffer mappings
--
--- @param bufnr? integer Buffer scope to include.
--- @param seq string Normalized key sequence.
---
--- @return boolean true if there exists any mapping longer than `seq` that starts with `seq`.
function M.has_child(bufnr, seq)
	local prefix_count = (GlobalPrefix[seq] or 0)

	if type(bufnr) == "number" then
		local bp = BufPrefix[bufnr]
		prefix_count = prefix_count + ((bp and bp[seq]) or 0)
	end

	local exact_count = GlobalMap[seq] and 1 or 0

	if type(bufnr) == "number" then
		local bm = BufMap[bufnr]
		if bm and bm[seq] then
			exact_count = exact_count + 1
		end
	end

	return prefix_count > exact_count
end

--- Remove all buffer-local mapping state.
---
--- @param bufnr integer Buffer number.
function M.delete_buf(bufnr)
	BufMap[bufnr] = nil
	BufPrefix[bufnr] = nil
end

-- helpers to return mappings in nvim's `get_keymap` format
local function build_keymap_entry(cmd)
	local metadata = cmd.metadata or {}
	local opts = cmd.opts or {}
	return {
		mode = cmd.mode,
		lhs = cmd.lhs,
		lhsraw = metadata.lhsraw or api.nvim_replace_termcodes(cmd.lhs, true, true, true),
		lhsrawalt = metadata.lhsrawalt or nil,
		rhs = cmd.rhs,
		callback = cmd.callback,
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

function M.get_keymap()
	local maps = nvim_get_keymap("i")
	for _, cmd in pairs(GlobalMap) do
		maps[#maps + 1] = build_keymap_entry(cmd)
	end
	return maps
end

--- Get effective buffer-local mappings in Neovim keymap format.
---
--- @param bufnr integer Buffer number.
---
--- @return table[]
function M.buf_get_keymap(bufnr)
	if type(bufnr) ~= "number" then
		error("bufnr must be a number")
	end
	local maps = nvim_buf_get_keymap(bufnr, "i")
	local tbl = BufMap[bufnr]
	if not tbl then
		return maps
	end
	for _, cmd in pairs(tbl) do
		maps[#maps + 1] = build_keymap_entry(cmd)
	end
	return maps
end

return M
