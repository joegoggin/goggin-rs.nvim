--- Public entrypoint for goggin-rs.nvim.
---
--- Exposes setup and configuration accessors while keeping configuration state
--- in the dedicated config module.

local config = require("goggin-rs.config")

local M = {}

--- Applies plugin configuration overrides.
---
---@param opts table|nil User configuration overrides.
---@return table config Active configuration table.
---
function M.setup(opts)
    return config.setup(opts)
end

--- Returns the active plugin configuration.
---
---@return table config Active configuration table.
---
function M.config()
    return config.get()
end

--- Returns a copy of the default plugin configuration.
---
---@return table defaults Default configuration table.
---
function M.defaults()
    return config.defaults()
end

return M
