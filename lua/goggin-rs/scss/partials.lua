--- SCSS partial lookup and source templates.
---
--- Builds simple class-block templates and resolves direct or fallback SCSS
--- partial filenames for generated Rust artifacts.

local fs = require("goggin-rs.infra.fs")
local path = require("goggin-rs.infra.path")

local M = {}

--- Builds a simple SCSS class block template.
---
---@param class_name string CSS class name.
---@return string[] lines SCSS source lines.
---
function M.build_class_template(class_name)
    return {
        string.format(".%s {", class_name),
        "}",
    }
end

--- Resolves a direct or parent-prefixed SCSS partial under a style directory.
---
---@param base_dir string Style directory to inspect.
---@param stem string Rust module stem.
---@param opts table|nil Options; set `parent_prefix = false` to skip parent-prefixed lookup.
---@return string|nil scss_path Matching SCSS partial path.
---
function M.resolve_partial_style(base_dir, stem, opts)
    local kebab_stem = stem:gsub("_", "-")
    local direct_match = path.join(base_dir, "_" .. kebab_stem .. ".scss")
    if fs.exists(direct_match) then
        return direct_match
    end

    local options = opts or {}
    if options.parent_prefix == false then
        return nil
    end

    local parent = path.basename(base_dir):gsub("_", "-")
    local prefixed_match = path.join(base_dir, "_" .. parent .. "-" .. kebab_stem .. ".scss")
    if fs.exists(prefixed_match) then
        return prefixed_match
    end

    return nil
end

return M
