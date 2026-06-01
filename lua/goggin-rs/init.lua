local config = require("goggin-rs.config")

local M = {}

function M.setup(opts)
    return config.setup(opts)
end

function M.config()
    return config.get()
end

function M.defaults()
    return config.defaults()
end

return M
