--- Page collection helpers.
---
--- Scans page roots for flat and module-layout page files and resolves their
--- paired page SCSS partials for picker workflows.

local path = require("goggin-rs.infra.path")
local rust = require("goggin-rs.rust")
local styles = require("goggin-rs.pages.styles")

local M = {}

--- Checks whether a page-relative Rust path belongs to a page components dir.
---
---@param rust_relative string Path relative to the configured pages root.
---@return boolean is_component_file Whether the path is nested under `components`.
---
local function is_page_component_file(rust_relative)
    return rust_relative:match("^components/") ~= nil or rust_relative:match("/components/") ~= nil
end

--- Builds a page entry for a Rust page component file.
---
---@param page_rs string Rust page path.
---@param component_name string Parsed page component name.
---@param paths table Resolved project paths.
---@return table|nil page Page entry, or nil when the file is not a supported page layout.
---
local function build_page_entry(page_rs, component_name, paths)
    local rust_relative = path.relative(paths.pages_dir, page_rs)
    if is_page_component_file(rust_relative) then
        return nil
    end

    local rust_parent_relative = vim.fn.fnamemodify(rust_relative, ":h")
    if rust_parent_relative == "." then
        rust_parent_relative = ""
    end

    local file_name = path.basename(page_rs)
    local module_name = vim.fn.fnamemodify(rust_relative, ":t:r")
    local is_module_layout = file_name == "page.rs"
    local module_relative_dir = module_name

    if is_module_layout then
        module_relative_dir = rust_parent_relative
        module_name = path.basename(module_relative_dir)
    elseif rust_parent_relative ~= "" then
        module_relative_dir = path.join(rust_parent_relative, module_name)
    end

    if module_relative_dir == "" then
        return nil
    end

    local page = {
        page_rs = page_rs,
        rust_path = page_rs,
        rust_relative = rust_relative,
        rust_parent_relative = rust_parent_relative,
        page_dir = path.join(paths.pages_dir, module_relative_dir),
        relative_dir = module_relative_dir,
        module_relative_dir = module_relative_dir,
        module_name = module_name,
        is_module_layout = is_module_layout,
        page_component_name = component_name,
        component_name = component_name,
        display_name = component_name:gsub("Page$", ""),
    }

    page.page_style_path = styles.resolve_scss_path(page, paths)
    page.scss_path = page.page_style_path

    return page
end

--- Collects Leptos pages under the configured page root.
---
---@param paths table Resolved project paths.
---@return table[] pages Sorted page entries.
---
function M.collect(paths)
    if not paths or not paths.pages_dir then
        return {}
    end

    local page_files = vim.fn.glob(path.join(paths.pages_dir, "**/*.rs"), true, true)
    local page_by_module = {}
    local pages = {}

    for _, page_rs in ipairs(page_files) do
        if path.basename(page_rs) ~= "mod.rs" then
            local component_name = rust.component_name_from_file(page_rs)

            if component_name and component_name:sub(-4) == "Page" then
                local page = build_page_entry(page_rs, component_name, paths)
                if page then
                    local existing = page_by_module[page.module_relative_dir]
                    if not existing or (page.is_module_layout and not existing.is_module_layout) then
                        page_by_module[page.module_relative_dir] = page
                    end
                end
            end
        end
    end

    for _, page in pairs(page_by_module) do
        table.insert(pages, page)
    end

    table.sort(pages, function(left, right)
        if left.display_name == right.display_name then
            return left.module_relative_dir < right.module_relative_dir
        end

        return left.display_name < right.display_name
    end)

    return pages
end

return M
