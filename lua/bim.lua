local M = {}

M.setup = function(opts)
	require("bim.ovveride").wrap()
	require("bim.core").setup()
end

return M
