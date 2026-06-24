--- Project layout discovery for Rust/Leptos applications.
---
--- Resolves configured source and style paths from candidate roots, supporting
--- both nested `web` layouts and direct web-root layouts.

local discovery = require("goggin-rs.project.discovery")
local project_paths = require("goggin-rs.project.paths")

local M = {}

--- Resolves project paths from the current Neovim context.
---
--- Searches candidate roots for either a nested `web` layout or a direct web
--- root layout. Returns a warning string when required paths cannot be found.
---
---@param required string[]|nil Path keys that must exist for a layout to match.
---@return table|nil paths Resolved project paths when a layout is found.
---@return string|nil err User-facing warning when required paths cannot be located.
---
function M.resolve(required)
    local required_paths = required or {}

    for _, root in ipairs(discovery.collect_search_roots()) do
        for _, paths in ipairs(project_paths.build_layouts(root)) do
            if project_paths.has_required_paths(paths, required_paths) then
                return paths
            end
        end
    end

    local description = project_paths.describe_required(required_paths)
    if description == "" then
        description = "required project paths"
    end

    return nil,
        "Could not locate web project paths for "
            .. description
            .. ". Expected either ./web/... from the repo root or ./... from the web root."
end

--- Resolves project paths and warns when required paths are unavailable.
---
---@param required string[] Path keys that must exist for a layout to match.
---@return table|nil paths Resolved project paths.
---
function M.resolve_or_notify(required)
    local paths, err = M.resolve(required)
    if not paths then
        vim.notify(err, vim.log.levels.WARN)
        return nil
    end

    return paths
end

return M
