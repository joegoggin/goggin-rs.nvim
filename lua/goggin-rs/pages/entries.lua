--- Page entry and page-local component collection.
---
--- Builds picker entries for a page and any generated page-local components,
--- including display labels and paired SCSS paths.

local fs = require("goggin-rs.infra.fs")
local path = require("goggin-rs.infra.path")
local rust = require("goggin-rs.rust")
local styles = require("goggin-rs.pages.styles")

local M = {}

--- Trims a page prefix from a page-local component label.
---
---@param component_name string Page-local component name.
---@param page_component_name string Page component name.
---@return string label Display label.
---
local function trim_page_prefix(component_name, page_component_name)
    if page_component_name:sub(-4) ~= "Page" then
        return component_name
    end

    local prefix = page_component_name
    if component_name:sub(1, #prefix) == prefix and #component_name > #prefix then
        return component_name:sub(#prefix + 1)
    end

    return component_name
end

--- Collects a page entry and its page-local component entries.
---
---@param page table Page entry from `collect`.
---@param paths table Resolved project paths.
---@return table[] entries Page entry first, followed by sorted component entries.
---
function M.collect_entries(page, paths)
    if not page then
        return {}
    end

    local entries = {
        {
            label = "Page",
            entry_type = "page",
            rust_path = page.page_rs or page.rust_path,
            rust_relative = page.rust_relative,
            scss_path = page.page_style_path or page.scss_path,
            component_name = page.page_component_name or page.component_name,
        },
    }

    if not page.is_module_layout or not paths or not paths.page_styles_dir then
        return entries
    end

    local components_dir = path.join(page.page_dir, "components")
    if fs.is_directory(components_dir) then
        local component_files = vim.fn.glob(path.join(components_dir, "**/*.rs"), true, true)

        for _, rust_path in ipairs(component_files) do
            if path.basename(rust_path) ~= "mod.rs" then
                local component_name = rust.component_name_from_file(rust_path)
                if component_name then
                    table.insert(entries, {
                        label = trim_page_prefix(component_name, page.page_component_name),
                        entry_type = "component",
                        rust_path = rust_path,
                        rust_relative = path.relative(paths.pages_dir, rust_path),
                        scss_path = styles.resolve_page_component_scss_path(page, rust_path, paths),
                        component_name = component_name,
                    })
                end
            end
        end
    end

    table.sort(entries, function(left, right)
        if left.entry_type == "page" and right.entry_type ~= "page" then
            return true
        end

        if right.entry_type == "page" and left.entry_type ~= "page" then
            return false
        end

        if left.label == right.label then
            return left.rust_relative < right.rust_relative
        end

        return left.label < right.label
    end)

    return entries
end

return M
