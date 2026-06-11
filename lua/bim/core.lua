local store = require("bim.store")
local type = type
local vim = vim
local v, api = vim.v, vim.api
local new_timer = (vim.uv or vim.loop).new_timer
local schedule, schedule_wrap, defer_fn = vim.schedule, vim.schedule_wrap, vim.defer_fn
local nvim_input, nvim_eval, replace_termcodes, nvim_win_get_cursor, nvim_get_current_line, nvim_buf_set_text, nvim_win_set_cursor =
	api.nvim_input,
	api.nvim_eval,
	api.nvim_replace_termcodes,
	api.nvim_win_get_cursor,
	api.nvim_get_current_line,
	api.nvim_buf_set_text,
	api.nvim_win_set_cursor

local min, max = math.min, math.max

local M = {}

-- state
local curr_seq = "" -- typed sequence string
local omodified = false -- buffer modified state before sequence started
local oword, ostart, oend, orow, ocurpos = nil, -1, -1, -1, -1
local timer = nil

local function reset_state()
	curr_seq = ""
	omodified = false
	oword, ostart, oend, orow, ocurpos = nil, -1, -1, -1, -1
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
end

local function execute_normal_command(cmd)
	local rhs, callback, opts = cmd.rhs, cmd.callback, cmd.opts or {}
	if callback then
		callback()
		return
	elseif not rhs or rhs == "" then
		return
	elseif opts.replace_keycodes then
		local rhsraw = cmd.rhsraw
		if rhsraw then
			rhs = cmd.rhsraw
		else
			rhs = replace_termcodes(rhs, true, true, true)
			cmd.rhsraw = rhs
		end
	end
	nvim_input(rhs)
end

local function execute_expression_command(cmd)
	local rhs, callback, opts = cmd.rhs, cmd.callback, cmd.opts or {}
	if callback then
		rhs = callback()
	end

	local function validate_string(str)
		if type(str) ~= "string" then
			vim.notify(
				"Bim: Expression command returned an invalid value: " .. tostring(str),
				vim.log.levels.ERROR,
				{ title = "Bim" }
			)
			return false
		end
		return true
	end

	if not validate_string(rhs) then
		return
	elseif rhs == "" then
		return
	end

	rhs = nvim_eval(rhs)
	if not validate_string(rhs) then
		return
	elseif rhs == "" then
		return
	end

	if opts.replace_keycodes then
		nvim_input(replace_termcodes(rhs, true, true, true))
	else
		nvim_input(rhs)
	end
end

local function execute_command(cmd)
	local opts = cmd.opts or {}
	if opts.expr then
		execute_expression_command(cmd)
	else
		execute_normal_command(cmd)
	end
end

local function start_timer(timeoutlen, cb)
	if not timer then
		timer = new_timer()
	end
	return timer:start(timeoutlen, 0, schedule_wrap(cb))
end

local function get_word_under_cursor()
	local cursor_pos = nvim_win_get_cursor(0)
	local col_0based = cursor_pos[2]
	local row_0based = cursor_pos[1] - 1

	local line = nvim_get_current_line()
	if line == "" then
		return nil, col_0based, col_0based + 1, row_0based, col_0based
	end

	local s = line:sub(1, col_0based):find("[^%s]+$") or col_0based + 1
	local e = line:find("^%s", col_0based + 1) or (#line + 1)

	return line:sub(s, e - 1), s - 1, e - 1, row_0based, col_0based
end

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

local function finalize_and_apply_mapping(cmd, bufnr)
	restore_original_word()
	reset_state()

	schedule(function()
		execute_command(cmd)
		if not omodified and api.nvim_buf_is_valid(bufnr) then
			api.nvim_set_option_value("modified", false, { buf = bufnr })
		end
	end)
end

local function process_input_char(char, bufnr)
	curr_seq = curr_seq .. char

	-- if no prefix in either buffer scope or global, there is no mapping
	if not store.has_prefix(bufnr, curr_seq) then
		reset_state()
		return
	elseif not oword and #curr_seq == 1 then
		omodified = api.nvim_get_option_value("modified", { buf = bufnr })
		oword, ostart, oend, orow, ocurpos = get_word_under_cursor()
	end
end

local function invoke_mapped_command(bufnr)
	local seq = curr_seq
	if seq == "" then
		return
	end

	-- on first character we wait the timeout to allow longer sequences
	if #seq == 1 then
		local seq_snapshot = seq

		start_timer(vim.o.timeoutlen or 300, function()
			local curr_cmd = store.get_command(bufnr, seq_snapshot)
			if curr_cmd then
				finalize_and_apply_mapping(curr_cmd, bufnr)
				return
			end
			reset_state()
		end)
	end

	local cmd = store.get_command(bufnr, seq)
	if not cmd then
		return
	elseif not store.has_child(bufnr, seq) then
		finalize_and_apply_mapping(cmd, bufnr)
	end
end

M.setup = function()
	local autocmd = api.nvim_create_autocmd
	local NAMESPACE = api.nvim_create_namespace("BimHandler")
	local GROUP = api.nvim_create_augroup("BimHandler", { clear = true })

	local inserting = false
	local inserted_char = ""
	local working_bufnr = -1

	local register_onkey = function(cb, opts)
		vim.on_key(cb, NAMESPACE, opts)
	end

	local unregister_onkey = function()
		vim.on_key(nil, NAMESPACE)
	end

	-- init once
	store.build(nil)

	autocmd({ "BufNew", "BufDelete" }, {
		group = GROUP,
		callback = function(args)
			if args.event == "BufDelete" then
				store.delete_buf(args.buf)
			else
				store.build(args.buf)
			end
		end,
	})

	autocmd({ "BufLeave", "WinLeave", "InsertLeave" }, {
		group = GROUP,
		callback = function(args)
			reset_state()
		end,
	})

	autocmd({ "InsertEnter", "InsertLeave" }, {
		group = GROUP,
		callback = function(args)
			if args.event == "InsertEnter" then
				register_onkey(function(key, typed)
					typing = true
					inserted_char = typed
				end)
			else
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
					else
						reset_state()
					end
				end
				return
			elseif working_bufnr ~= args.buf then
				reset_state()
				return
			elseif not inserting then
				reset_state()
				return
			end
			inserting = false

			-- Make sure this will  run after all autocmd and vim.schedule
			defer_fn(function()
				invoke_mapped_command(args.buf)
			end, 0)
		end,
	})
end

return M
