local type = type
-- override.lua
local M = {}

--- Check if the mode is insert mode
--- @param mode string or table of strings representing modes
--- @return boolean true if the mode is insert mode, false otherwise
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

	---@diagnostic disable-next-line: duplicate-set-field
	keymap.set = function(mode, lhs, rhs, opts)
		-- original_set(mode, lhs, rhs, opts)
		if is_insert_mode(mode) then
			if opts.expr and opts.replace_keycodes ~= false then
				opts.replace_keycodes = true
			end

			if opts.remap == nil then
				-- default remap value is false
				opts.noremap = true
			else
				-- remaps behavior is opposite of noremap option.
				opts.noremap = not opts.remap
				opts.remap = nil ---@type boolean?
			end

			if type(rhs) == "function" then
				opts.callback = rhs
				rhs = ""
			end

			if opts.buffer then
				--- unsupported now
				-- local bufnr = opts.buffer == true and 0 or opts.buffer --[[@as integer]]
				-- opts.buffer = nil ---@type integer?
			else
				opts.buffer = nil
				trie.insert_mapping(lhs, rhs, opts)
			end
		end
	end

	---@diagnostic disable-next-line: duplicate-set-field
	keymap.del = function(mode, lhs, opts)
		-- original_del(mode, lhs, opts)
		if is_insert_mode(mode) then
			trie.remove_mapping(lhs)
		end
	end
end

return M
