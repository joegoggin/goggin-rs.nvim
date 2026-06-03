--- Component style pairing helpers.
---
--- Maps component Rust paths to direct or parent-prefixed SCSS partial paths
--- under the configured component style root.

local path = require("goggin-rs.infra.path")
local scss = require("goggin-rs.scss")

local M = {}

--- Resolves the paired SCSS partial for a component Rust file.
---
--- Direct partial names win first, then nested parent-prefixed names are
--- checked for compatibility with the source config behavior.
---
---@param rust_path string Component Rust file path.
---@param paths table Resolved project paths.
---@return string|nil scss_path Matching SCSS path when one exists.
---
function M.resolve_scss_path(rust_path, paths)
    if not paths or not paths.components_dir or not paths.styles_components_dir then
        return nil
    end

    local relative = path.relative(paths.components_dir, rust_path)
    if relative == rust_path then
        return nil
    end

    local relative_dir = vim.fn.fnamemodify(relative, ":h")
    if relative_dir == "." then
        relative_dir = ""
    end

    local stem = vim.fn.fnamemodify(relative, ":t:r")
    local base_dir = path.join(paths.styles_components_dir, relative_dir)

    return scss.resolve_partial_style(base_dir, stem, { parent_prefix = relative_dir ~= "" })
end

return M
