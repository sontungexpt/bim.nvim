local M = {}

function M.setup()
	local handler = require("bim.handler")
	local override = require("bim.ovveride")

	handler.setup()
	override.wrap()
end

return M
