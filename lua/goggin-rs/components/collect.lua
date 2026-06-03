--- Component collection helpers.
---
--- Scans component source roots for Leptos component files and resolves their
--- paired SCSS partials for picker workflows.

local path = require("goggin-rs.infra.path")
local rust = require("goggin-rs.rust")
local styles = require("goggin-rs.components.styles")

local M = {}

--- Collects Leptos components under the configured component root.
---
---@param paths table Resolved project paths.
---@return table[] components Sorted component entries.
---
function M.collect(paths)
    if not paths or not paths.components_dir then
        return {}
    end

    local rust_files = vim.fn.glob(path.join(paths.components_dir, "**/*.rs"), true, true)
    local components = {}

    for _, rust_path in ipairs(rust_files) do
        if path.basename(rust_path) ~= "mod.rs" then
            local component_name = rust.component_name_from_file(rust_path)

            if component_name then
                local rust_relative = path.relative(paths.components_dir, rust_path)

                table.insert(components, {
                    component_name = component_name,
                    rust_path = rust_path,
                    rust_relative = rust_relative,
                    scss_path = styles.resolve_scss_path(rust_path, paths),
                })
            end
        end
    end

    table.sort(components, function(left, right)
        if left.component_name == right.component_name then
            return left.rust_relative < right.rust_relative
        end

        return left.component_name < right.component_name
    end)

    return components
end

return M
