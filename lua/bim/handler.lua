local trie = require("bim.trie")

local vim = vim
local uv, v, api = vim.uv or vim.loop, vim.v, vim.api
---@diagnostic disable-next-line: undefined-field
local new_timer = uv.new_timer
local schedule, schedule_wrap = vim.schedule, vim.schedule_wrap
local nvim_input, nvim_win_get_cursor, nvim_get_current_line, nvim_buf_set_text, nvim_win_set_cursor, nvim_command =
	api.nvim_input,
	api.nvim_win_get_cursor,
	api.nvim_get_current_line,
	api.nvim_buf_set_text,
	api.nvim_win_set_cursor,
	api.nvim_command
local min, max = math.min, math.max

local M = {}

local TIMEOUTLEN = vim.o.timeoutlen or 300
local current_seq = {}
local current_node = trie.get_trie()
local original_word = nil
local timer = nil
local original_s, original_e = -1, -1
local original_row = -1
local executed = false

local function reset()
	executed = false
	current_seq = {}
	current_node = trie.get_trie()
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
end

local function execute_command(cmd)
	if cmd.expr and type(cmd.value) == "function" then
		local ok, result = pcall(cmd.value)
		if ok and type(result) == "string" then
			nvim_input(result)
		end
	elseif cmd.type == "string" then
		nvim_input(cmd.value)
	elseif cmd.type == "command" then
		nvim_command(cmd.value:sub(2)) -- remove ':'
	elseif cmd.type == "function" then
		local ok, result = pcall(cmd.value)
		if ok and type(result) == "string" then
			nvim_input(result)
		end
	end
end

local function start_timer(timeoutlen, cb)
	timer = new_timer()
	return timer:start(timeoutlen, 0, schedule_wrap(cb))
end

--- Get the current word under the cursor
--- If the cursor is not on a word, return nil_wrap
--- and the start and end position of the word
--- If the cursor is on a word, return the word,
--- the start and end position of the word,
--- @return string|nil The word under the cursor
--- @return integer The start position of the word (0-indexed)
--- @return integer The end position of the word (0-indexed) (exclusive)
--- @return integer The row of the word (0-indexed)
local function get_current_word()
	local cursor_pos = nvim_win_get_cursor(0)
	local col = cursor_pos[2]
	local row = cursor_pos[1]

	local line = nvim_get_current_line()
	if line == "" then
		return nil, col, col + 1, row
	end
	-- find the start and end of the word
	-- by looking for spaces
	local s = line:sub(1, col):find("[^%s]+$")
	if not s then
		return nil, col, col + 1, row
	end

	local e = line:find("^%s", col + 1) or (#line + 1)

	return line:sub(s, e - 1), s - 1, e - 1, row - 1
end

local function restore_cursor_word()
	local curr_word, s, e, row = get_current_word()

	if not curr_word or row ~= original_row then
		return
	elseif s == original_s and e == original_e and row == original_row and curr_word == original_word then
		return
	end
	local rs = min(original_s, s)
	local re = max(original_e, e)

	nvim_buf_set_text(0, original_row, rs, original_row, re, { original_word })
	nvim_win_set_cursor(0, { original_row, original_e })
end

local function on_char(char)
	current_seq[#current_seq + 1] = char

	--- make sure the current node is not nil
	if not current_node then
		current_node = trie.get_trie()
	end

	current_node = current_node[char]

	if not current_node then
		reset()
		return
	elseif not original_word or original_word == "" then
		original_word, original_s, original_e, original_row = get_current_word()
	end

	if trie.get_command(current_node) then
		-- promise to execute the command
		executed = true
	end
end

local finalize_mapping_execution = function(cmd)
	restore_cursor_word()
	reset()
	schedule(function()
		execute_command(cmd)
	end)
end

local execute_mapping = function()
	if not executed then
		return
	end
	local cmd = trie.get_command(current_node)

	-- no more child then execute command
	if not trie.has_child(current_node) then
		finalize_mapping_execution(cmd)
		return
	end

	start_timer(TIMEOUTLEN, function()
		finalize_mapping_execution(cmd)
	end)
end

M.setup = function()
	local autocmd = api.nvim_create_autocmd
	local group = api.nvim_create_augroup("BimHandler", { clear = true })
	local inserting = false

	autocmd({ "InsertCharPre", "TextChangedI", "BufLeave", "WinLeave", "CursorMovedI" }, {
		group = group,
		callback = function(args)
			local event = args.event
			if event == "BufLeave" or args.event == "WinLeave" then
				reset()
				return
			elseif event == "InsertCharPre" then
				inserting = true
				local char = v.char
				if char:match("^[%w%p ]$") then
					on_char(char)
				end
				return
			elseif not inserting then
				-- if moved cursor in insert mode,
				-- but not inserting any char,
				reset()
				-- remove char
				return
			elseif event == "TextChangedI" or event == "CursorMovedI" then
				inserting = false
				execute_mapping()
			end
		end,
	})
end

return M
