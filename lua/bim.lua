local M = {}

M.setup = function(opts)
	local store = require("bim.store")
	store.build(nil, true)

	require("bim.ovveride").wrap()
	require("bim.handler").setup()
end

return M
