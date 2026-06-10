local M = {}

M.setup = function()
	require("bim.handler").setup()
	require("bim.ovveride").wrap()
end

return M
