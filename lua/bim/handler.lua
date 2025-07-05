local trie = require("bim.trie")
local type = type
local vim = vim
local v, api = vim.v, vim.api
---@diagnostic disable-next-line: undefined-field
local new_timer = (vim.uv or vim.loop).new_timer
local cursor_move_accepted = false
local schedule, schedule_wrap, defer_fn = vim.schedule, vim.schedule_wrap, vim.defer_fn
local nvim_get_mode, nvim_input, nvim_eval, replace_termcodes, nvim_win_get_cursor, nvim_get_current_line, nvim_buf_set_text, nvim_win_set_cursor, nvim_command =
	api.nvim_get_mode,
	api.nvim_input,
	api.nvim_eval,
	api.nvim_replace_termcodes,
	api.nvim_win_get_cursor,
	api.nvim_get_current_line,
	api.nvim_buf_set_text,
	api.nvim_win_set_cursor,
	api.nvim_command
local min, max = math.min, math.max

local M = {}

local TIMEOUTLEN = vim.o.timeoutlen or 300
local current_seq = {}
local bcurr_node, curr_node = nil, nil
local oword, ostart, oend, orow, ocurpos = nil, -1, -1, -1, -1
local timer = nil

--- public api for other plugins
function M.trigger_cursor_move_accepted()
	cursor_move_accepted = true
end

local function reset_state()
	current_seq = {}
	cursor_move_accepted = false
	bcurr_node, curr_node = nil, trie.get_trie()
	oword, ostart, oend, orow, ocurpos = nil, -1, -1, -1, -1
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
end

--- Execute the command associated with the current sequence
--- @param cmd Cmd The command to execute_command
local function execute_command(cmd)
	local rhs, callback, opts = cmd.rhs, cmd.callback, cmd.opts or {}

	local output = rhs
	if callback then
		output = callback()
		if not opts.expr then
			return
		end
	end

	if opts.expr and type(output) == "string" then
		output = nvim_eval(output)
	end

	if type(output) == "string" and output ~= "" then
		if opts.replace_keycodes then
			local rhsraw = cmd.rhsraw
			if rhsraw then
				output = cmd.rhsraw
			else
				output = replace_termcodes(output, true, true, true)
				-- cache the raw lhs for later use
				cmd.rhsraw = output
			end
		end
		nvim_input(output)
	end
end

--- Create a new timer and start ít
--- @param timeoutlen integer The timeout length in milliseconds
--- @param cb function The callback function to be called when the timer expires
local function start_timer(timeoutlen, cb)
	if not timer then
		timer = new_timer()
	end
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
--- @return integer The column of the word (0-indexed)
local function get_word_under_cursor()
	local cursor_pos = nvim_win_get_cursor(0)
	local col_0based = cursor_pos[2]
	local row_0based = cursor_pos[1] - 1

	local line = nvim_get_current_line()
	if line == "" then
		return nil, col_0based, col_0based + 1, row_0based, col_0based
	end
	-- find the start and end of the word
	-- by looking for spaces
	local s = line:sub(1, col_0based):find("[^%s]+$") or col_0based + 1
	local e = line:find("^%s", col_0based + 1) or (#line + 1)

	return line:sub(s, e - 1), s - 1, e - 1, row_0based, col_0based
end

--- Restore the original word under the cursor
local function restore_original_word()
	local curr_word, s, e, row = get_word_under_cursor()

	if not curr_word or row ~= orow then
		return
	elseif s == ostart and e == oend and curr_word == oword then
		return
	end
	local rs = min(ostart, s)
	local re = max(oend, e)

	nvim_buf_set_text(0, orow, rs, orow, re, { oword })
	nvim_win_set_cursor(0, { orow + 1, ocurpos })
end

--- Reset the state of the handler
--- This function is called when the user leaves the insert mode
--- @param char string The character that was pressed
--- @param bufnr integer The buffer number
local function process_input_char(char, bufnr)
	current_seq[#current_seq + 1] = char

	--- make sure the current node is not nil
	if not curr_node then
		curr_node = trie.get_trie()
	end

	if not bcurr_node then
		bcurr_node = trie.get_buf_trie(bufnr)
	end

	curr_node = curr_node[char]
	bcurr_node = bcurr_node[char]

	if not bcurr_node and not curr_node then
		reset_state()
		return
	elseif not oword and #current_seq == 1 then
		-- if this is the first character of the sequence,
		oword, ostart, oend, orow, ocurpos = get_word_under_cursor()
	end
end

local finalize_and_apply_mapping = function(cmd)
	restore_original_word()
	reset_state()
	schedule(function()
		execute_command(cmd)
	end)
end

--- Invoke the mapped command based on the current sequence
--- This function is called when the user has finished typing a sequence
--- and the command is ready to be executed
local invoke_mapped_command = function()
	local priority_node = bcurr_node or curr_node
	if not priority_node then
		return
	end

	if #current_seq == 1 then
		start_timer(TIMEOUTLEN, function()
			local curr_cmd = priority_node and trie.get_command(priority_node)
			if curr_cmd then
				-- if case that parent node also has command so need to wait for timeout
				-- and if no leaf node then execute the command from parent
				finalize_and_apply_mapping(curr_cmd)
				return
			end
			reset_state()
		end)
	end

	local cmd = trie.get_command(priority_node)
	if not cmd then
		return
	elseif not trie.has_child(priority_node) then
		-- no more child then execute command
		finalize_and_apply_mapping(cmd)
	end
end

--- Setup the autocmds for the bim handler
M.setup = function()
	local autocmd = api.nvim_create_autocmd
	local NAMESPACE = api.nvim_create_namespace("BimHandler")
	local GROUP = api.nvim_create_augroup("BimHandler", { clear = true })

	local inserting = false
	local inserted_char = ""
	local working_bufnr = -1

	local reset_vars = function()
		inserted_char = ""
		working_bufnr = -1
	end

	local register_onkey = function(cb, opts)
		vim.on_key(cb, NAMESPACE, opts)
	end

	local unregister_onkey = function()
		vim.on_key(nil, NAMESPACE)
	end

	--- core
	trie.build_trie()

	autocmd({ "BufNew", "BufDelete" }, {
		group = GROUP,
		callback = function(args)
			if args.event == "BufDelete" then
				trie.delete_buf(args.buf)
			else
				trie.build_trie(args.buf)
			end
		end,
	})

	autocmd({ "BufLeave", "WinLeave", "InsertLeave" }, {
		group = GROUP,
		callback = function(args)
			if args.event == "CursorMovedI" and (inserting or cursor_move_accepted or nvim_get_mode().mode ~= "i") then
				return
			end
			reset_state()
		end,
	})

	--- Why not handle all logic in vim.onkey?
	--- > Because we don't want it change the behavior of InsertCharPre autocmd
	--- > If handle all on onkey we need to return "" for some case
	--- and it will break the InsertCharPre autocmd
	api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
		group = GROUP,
		callback = function(args)
			if args.event == "InsertEnter" then
				---@diagnostic disable-next-line: unused-local
				register_onkey(function(key, typed)
					inserted_char = key
				end)
			else
				-- unregister the key handler
				unregister_onkey()
			end
		end,
	})
	autocmd({ "InsertCharPre", "TextChangedI" }, {
		group = GROUP,
		callback = function(args)
			if args.event == "InsertCharPre" then
				if inserted_char == v.char then
					working_bufnr = args.buf
					inserting = true

					if inserted_char:match("^[%w%p ]$") then
						process_input_char(inserted_char, args.buf)
					end
				end
				return
			elseif working_bufnr ~= args.buf then
				reset_state()
				reset_vars()
				return
			elseif not inserting then
				-- remove char
				reset_state()
				reset_vars()
				return
			end
			-- elseif event == "TextChangedI" or event == "CursorMovedI" then
			inserting = false

			-- ensure it will run at last of all autocmd TextChangedI event
			defer_fn(function()
				invoke_mapped_command()
			end, 0)
			reset_vars()
		end,
	})
end

return M
