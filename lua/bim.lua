local M = {}

function M.setup()
	local trie = require("bim.trie")
	local handler = require("bim.handler")
	local override = require("bim.ovveride")

	trie.build_trie()
	handler.setup()
	-- override.wrap()
end

return M
