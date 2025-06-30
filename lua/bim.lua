local M = {}

function M.setup()
	local trie = require("bim.trie")
	local handler = require("bim.handler")
	-- local override = require("bim.override")

	trie.build_trie()
	handler.setup()
	-- override.wrap()

	-- vim.api.nvim_create_user_command("InsertMapperReload", function()
	-- 	trie.build_trie()
	-- 	print("Insert mappings reloaded.")
	-- end, {})
end

return M
