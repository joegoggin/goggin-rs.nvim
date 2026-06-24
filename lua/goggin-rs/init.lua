--- Public entrypoint for goggin-rs.nvim.
---
--- Exposes setup and configuration accessors while keeping configuration state
--- in the dedicated config module.

local commands = require("goggin-rs.commands")
local config = require("goggin-rs.config")

local M = {}

--- Applies plugin configuration overrides.
---
---@param opts table|nil User configuration overrides.
---@return table config Active configuration table.
---
function M.setup(opts)
    local active_config = config.setup(opts)

    if active_config.commands and active_config.commands.enabled == false then
        commands.unregister()
    else
        commands.register()
    end

    return active_config
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
