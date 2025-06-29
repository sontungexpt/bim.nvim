-- input_handler.lua
local M = {}

local current_seq = {}
local current_node = nil
local original_word = ""
local timeout_timer = nil
local timeoutlen = vim.o.timeoutlen or 1000

local trie = require("insert_mapper.mapping_trie")

local function reset()
	current_seq = {}
	current_node = trie.get_trie()
	if timeout_timer then
		timeout_timer:stop()
		timeout_timer:close()
		timeout_timer = nil
	end
end

local function get_current_word()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local s = line:sub(1, col):find("[^%w%p]*$") or 1
	local e = line:find("[%s]", col + 1) or (#line + 1)
	return line:sub(s, e - 1), s - 1, e - 2
end

function M.on_char(char)
	if not current_node then
		current_node = trie.get_trie()
	end

	vim.schedule(function()
		vim.api.nvim_input(char)
	end)
	table.insert(current_seq, char)

	if current_node[char] then
		current_node = current_node[char]
		if current_node.command then
			original_word, word_start, word_end = get_current_word()

			timeout_timer = vim.loop.new_timer()
			timeout_timer:start(timeoutlen, 0, function()
				vim.schedule(function()
					local row = vim.api.nvim_win_get_cursor(0)[1]
					vim.api.nvim_buf_set_text(0, row - 1, word_start, row - 1, word_end + 1, { "" })
					vim.api.nvim_input(current_node.command)
					reset()
				end)
			end)
		end
	else
		reset()
	end
end

return M
