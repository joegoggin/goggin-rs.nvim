--- Configured project path resolution and validation.
---
--- Builds concrete project path tables from configured relative paths and
--- validates required paths for discovered layouts.

local config = require("goggin-rs.config")
local fs = require("goggin-rs.infra.fs")
local path = require("goggin-rs.infra.path")

local M = {}

---@type table<string, { label: string, type: "directory"|"file" }>
M.PROJECT_PATHS = {
    components_dir = { label = "src/components", type = "directory" },
    styles_components_dir = { label = "styles/components", type = "directory" },
    pages_dir = { label = "src/pages", type = "directory" },
    page_styles_dir = { label = "styles/pages", type = "directory" },
    app_path = { label = "src/app.rs", type = "file" },
}

--- Resolves a configured path relative to a candidate web root.
---
---@param web_root string Candidate web root.
---@param configured_path string Configured absolute or relative path.
---@return string resolved Absolute path without trailing slashes.
---
local function resolve_configured_path(web_root, configured_path)
    if path.is_absolute(configured_path) then
        return (configured_path:gsub("/+$", ""))
    end

    return (path.join(web_root, configured_path):gsub("/+$", ""))
end

--- Builds concrete project paths for a candidate web root.
---
---@param web_root string Candidate web root.
---@return table paths Resolved project path table.
---
function M.build_paths(web_root)
    local configured_paths = config.get().paths or {}
    local resolved_paths = {
        web_root = web_root,
    }

    for key in pairs(M.PROJECT_PATHS) do
        resolved_paths[key] = resolve_configured_path(web_root, configured_paths[key])
    end

    return resolved_paths
end

--- Builds supported layout candidates for a root.
---
---@param root string Candidate root directory.
---@return table[] layouts Candidate path tables for nested and direct layouts.
---
function M.build_layouts(root)
    return {
        M.build_paths(path.join(root, "web")),
        M.build_paths(root),
    }
end

--- Checks whether a resolved path satisfies a required key.
---
---@param resolved_paths table Resolved project path table.
---@param key string Required path key.
---@return boolean satisfies Whether the path exists with the expected type.
---
local function path_satisfies(resolved_paths, key)
    local value = resolved_paths[key]
    if not value then
        return false
    end

    if M.PROJECT_PATHS[key] and M.PROJECT_PATHS[key].type == "file" then
        return fs.exists(value)
    end

    return fs.is_directory(value)
end

--- Checks whether every required path exists in a candidate layout.
---
---@param resolved_paths table Resolved project path table.
---@param required string[] Required path keys.
---@return boolean has_paths Whether all required paths are satisfied.
---
function M.has_required_paths(resolved_paths, required)
    for _, key in ipairs(required) do
        if not path_satisfies(resolved_paths, key) then
            return false
        end
    end

    return true
end

--- Builds a user-facing description of required path keys.
---
---@param required string[] Required path keys.
---@return string description Sorted, de-duplicated path labels.
---
function M.describe_required(required)
    local labels = {}
    local seen = {}

    for _, key in ipairs(required) do
        local path_config = M.PROJECT_PATHS[key]
        local label = path_config and path_config.label or key
        if not seen[label] then
            seen[label] = true
            table.insert(labels, label)
        end
    end

    table.sort(labels)
    return table.concat(labels, ", ")
end

return M
