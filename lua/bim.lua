local M = {}

function M.setup()
	local trie = require("bim.trie")
	local handler = require("bim.handler")
	local override = require("bim.override")

	trie.build_trie()
	-- vim.notify(vim.inspect(trie.get_trie()))
	handler.setup()
	override.wrap()
end

return M
