local api = vim.api
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
	local original_del = keymap.del
	local nvim_set_keymap = api.nvim_set_keymap
	local nvim_buf_set_keymap = api.nvim_buf_set_keymap

	---@diagnostic disable-next-line: duplicate-set-field
	keymap.set = function(mode, lhs, rhs, opts)
		---@cast mode string[]
		mode = type(mode) == "string" and { mode } or mode

		opts = vim.deepcopy(opts)

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
			local bufnr = opts.buffer == true and 0 or opts.buffer --[[@as integer]]
			opts.buffer = nil ---@type integer?
			for _, m in ipairs(mode) do
				if m == "i" then
					if not trie.buf_set_keymap(bufnr, lhs, rhs, opts) then
						nvim_buf_set_keymap(bufnr, m, lhs, rhs, opts)
					end
				else
					nvim_buf_set_keymap(bufnr, m, lhs, rhs, opts)
				end
			end
		else
			opts.buffer = nil
			for _, m in ipairs(mode) do
				if m == "i" then
					if not trie.set_keymap(lhs, rhs, opts) then
						nvim_set_keymap(m, lhs, rhs, opts)
					end
				else
					nvim_set_keymap(m, lhs, rhs, opts)
				end
			end
		end
	end

	---@diagnostic disable-next-line: duplicate-set-field, unused-local
	keymap.del = function(mode, lhs, opts)
		-- original_del(mode, lhs, opts)
		if is_insert_mode(mode) and trie.remove_mapping(lhs) then
			return
		end
		original_del(mode, lhs, opts)
	end
end

return M
