local api = vim.api
local keymap = vim.keymap
local original_get_keymap = api.nvim_get_keymap
local original_buf_get_keymap = api.nvim_buf_get_keymap

local type = type

local M = {
	nvim_buf_get_keymap = original_buf_get_keymap,
	nvim_get_keymap = original_get_keymap,
	keymap_set = keymap.set,
	keymap_del = keymap.del,
}

function M.wrap()
	local trie = require("bim.trie")
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
	keymap.del = function(modes, lhs, opts)
		-- original_del(mode, lhs, opts)
		opts = opts or {}
		--- @cast modes string[]
		modes = type(modes) == "string" and { modes } or modes

		local buffer = false ---@type false|integer
		if opts.buffer ~= nil then
			buffer = opts.buffer == true and 0 or opts.buffer --[[@as integer]]
		end

		if buffer == false then
			for _, mode in ipairs(modes) do
				if mode == "i" then
					if not trie.del_keymap(lhs) then
						api.nvim_del_keymap(mode, lhs)
					end
				else
					api.nvim_del_keymap(mode, lhs)
				end
			end
		else
			for _, mode in ipairs(modes) do
				if mode == "i" then
					if not trie.del_keymap(lhs) then
						api.nvim_buf_del_keymap(buffer, mode, lhs)
					end
				else
					api.nvim_buf_del_keymap(buffer, mode, lhs)
				end
			end
		end
	end

	---@diagnostic disable-next-line: duplicate-set-field
	api.nvim_buf_get_keymap = function(bufnr, mode)
		if mode == "i" then
			return trie.buf_get_keymap(bufnr)
		else
			return original_buf_get_keymap(bufnr, mode)
		end
	end

	---@diagnostic disable-next-line: duplicate-set-field
	api.nvim_get_keymap = function(mode)
		if mode == "i" then
			return trie.get_keymap()
		else
			return original_get_keymap(mode)
		end
	end
end

return M
