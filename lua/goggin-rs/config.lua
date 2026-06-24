--- Configuration state for goggin-rs.nvim.
---
--- Stores default project layout paths and merges user-provided overrides for
--- project discovery.

local M = {}

---@type table
local defaults = {
    commands = {
        enabled = true,
    },
    paths = {
        components_dir = "src/components",
        styles_components_dir = "styles/components",
        pages_dir = "src/pages",
        page_styles_dir = "styles/pages",
        app_path = "src/app.rs",
    },
}

local current = vim.deepcopy(defaults)

--- Merges user options with the default plugin configuration.
---
---@param opts table|nil User configuration overrides.
---@return table config Merged configuration table.
---
local function merge(opts)
    return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

--- Applies plugin configuration overrides.
---
---@param opts table|nil User configuration overrides.
---@return table config Active configuration table.
---
function M.setup(opts)
    current = merge(opts)
    return current
end

--- Returns the active plugin configuration.
---
---@return table config Active configuration table.
---
function M.get()
    return current
end

--- Returns a copy of the default plugin configuration.
---
---@return table defaults Default configuration table.
---
function M.defaults()
    return vim.deepcopy(defaults)
end

return M
